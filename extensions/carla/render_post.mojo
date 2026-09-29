# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The camera effects of a CARLA RGB image that ThreeMojo's composer lacks.

Each effect reads and writes a `RenderTarget` in place, between the
composer's own passes; `camera_render` runs them in order. They are
well-known image effects, written here from their textbook forms:

- **Height fog** mixes each pixel toward the fog's color by the light its
  ray loses in `render_weather.HeightFog`. The fog's color is the sky
  just above the horizon in the ray's direction, plus sunlight scattered
  forward by a Henyey-Greenstein phase function.
- **Rain** draws streaks of light at random places and depths. A streak
  behind a surface is hidden by it.
- **Metering** is a camera's auto exposure: a histogram of the log
  luminance, with the darkest and the brightest tenth dropped, and the
  mean of the rest.
- **White balance** scales the three channels by fixed gains.
- **Gamma** raises the tone-mapped light to a power, so that a gamma other
  than 2.2 changes the image's contrast.
- **The lens** bends the image with a radial distortion, `k r^2 + kcube
  r^3`, fitted so the corners stay in the frame, and darkens the rim by a
  circle falloff.
- **A wide-angle lens** draws the image from a cube of the scene around
  the camera, through one of CARLA's camera models.

The sizes and gains are this port's own choices.
"""

from extensions.carla.render_weather import HeightFog, RainSettings
from math.matrix4 import Matrix4
from math.utils import SeededRandom
from math.vector3 import Vector3
from render.cube_texture import CubeTexture
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import atan, asin, cos, exp, isfinite, log2, pow, sin, sqrt, tan
from units.si import METER, PER_METER, Angle, Length, RADIAN

# How far a ray that meets nothing runs through the fog.
comptime SKY_DISTANCE = Length(3000, METER)
# How high above the horizon the fog reads the sky's color, as the rise
# of a direction whose level part is the ray's.
comptime FOG_SKY_RISE = Float32(0.05)
# The forward scattering of the fog's droplets.
comptime FOG_PHASE_G = Float32(0.6)
# What the sunlight scattered by the fog is scaled by.
comptime FOG_SUN_SCALE = Float32(0.08)
# The log2 luminance a histogram's bins cover, and how many there are.
comptime HISTOGRAM_LOW = Float32(-14)
comptime HISTOGRAM_HIGH = Float32(6)
comptime HISTOGRAM_BINS = 80
# The share of pixels a histogram drops at each end.
comptime HISTOGRAM_TRIM = Float32(0.1)
# How near and far the rain streaks fall, and a near streak's length as a
# share of the image's height.
comptime RAIN_NEAR = Float32(1.5)
comptime RAIN_FAR = Float32(25)
comptime RAIN_LENGTH = Float32(0.03)
# What CARLA's lens sizes are scaled by, so the default lens bends the
# corners by about two percent.
comptime LENS_GAIN = Float32(0.25)


def luminance(color: FloatColor) -> Float32:
    """Return a linear color's luminance, with Rec. 709 weights.

    Args:
        color: The color.

    Returns:
        The luminance.
    """
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


def henyey_greenstein(cos_theta: Float32, g: Float32) -> Float32:
    """Return the Henyey-Greenstein phase function.

    Args:
        cos_theta: The cosine of the angle between the light's way and the
            view's way back to it.
        g: The anisotropy, from -1 to 1.

    Returns:
        The phase, per steradian.
    """
    var denominator = 1 + g * g - 2 * g * cos_theta
    return (1 - g * g) / (
        4 * Float32(3.141592653589793) * pow(denominator, Float32(1.5))
    )


struct ViewRays(ImplicitlyCopyable):
    """What turns a pixel and its depth into a ray and a distance."""

    var width: Int
    var height: Int
    # The inverse of the projection, and the camera's world matrix.
    var unproject: Matrix4
    var world: Matrix4
    var eye: Vector3

    def __init__(
        out self, width: Int, height: Int, projection: Matrix4, view: Matrix4
    ):
        """Hold the inverses of a camera's matrices.

        Args:
            width: The image's width.
            height: The image's height.
            projection: The camera's projection.
            view: The camera's view matrix.
        """
        self.width = width
        self.height = height
        self.unproject = projection
        self.unproject.invert()
        self.world = view
        self.world.invert()
        self.eye = Vector3.from_matrix_position(self.world)

    def view_point(self, x: Int, y: Int, depth: Float32) -> Vector3:
        """Return the camera-space point of a pixel at a window depth.

        Args:
            x: The column.
            y: The row, down from the top.
            depth: The window depth, zero to one.

        Returns:
            The point, minus z in front of the camera.
        """
        var u = (Float32(x) + 0.5) / Float32(self.width) * 2 - 1
        var v = 1 - (Float32(y) + 0.5) / Float32(self.height) * 2
        return self.unproject.transform_point(Vector3(u, v, depth * 2 - 1))

    def direction(self, x: Int, y: Int) -> Vector3:
        """Return the unit world direction through a pixel.

        Args:
            x: The column.
            y: The row, down from the top.

        Returns:
            The direction.
        """
        var far = self.world.transform_direction(self.view_point(x, y, 1))
        far.normalize()
        return far

    def distance(self, x: Int, y: Int, depth: Float32) -> Length:
        """Return how far the surface seen at a pixel is from the camera.

        Args:
            x: The column.
            y: The row, down from the top.
            depth: The window depth; one or more, or not finite, for the
                sky.

        Returns:
            The distance, or `SKY_DISTANCE` for the sky.
        """
        if not isfinite(depth) or depth >= 1:
            return SKY_DISTANCE
        return Length(self.view_point(x, y, depth).length(), METER)


def fog_color(
    horizon: FloatColor,
    sun: Vector3,
    sun_light: FloatColor,
    fog: HeightFog,
    direction: Vector3,
) -> FloatColor:
    """Return the light the fog sends toward the camera along a ray.

    Args:
        horizon: The sky's color at the horizon.
        sun: The unit direction toward the sun.
        sun_light: The sunlight's color times its intensity.
        fog: The fog; its scattering is read.
        direction: The unit direction of the ray from the camera.

    Returns:
        The horizon's color plus the sunlight scattered along the ray.
    """
    var cos_theta = (
        direction.x * sun.x + direction.y * sun.y + direction.z * sun.z
    )
    var scatter = (
        henyey_greenstein(cos_theta, FOG_PHASE_G)
        * fog.scattering
        * FOG_SUN_SCALE
    )
    return FloatColor(
        horizon.r + sun_light.r * scatter,
        horizon.g + sun_light.g * scatter,
        horizon.b + sun_light.b * scatter,
    )


def apply_height_fog(
    mut frame: RenderTarget,
    rays: ViewRays,
    fog: HeightFog,
    sky: CubeTexture,
    sun: Vector3,
    sun_light: FloatColor,
    ground: Length,
):
    """Mix every pixel toward the fog by the light its ray loses.

    The fog takes the sky's color low in the ray's own direction, so it
    glows warm toward a low sun and stays blue away from it.

    Args:
        frame: The frame, changed in place.
        rays: The camera's rays.
        fog: The fog.
        sky: The sky.
        sun: The unit direction toward the sun.
        sun_light: The sunlight's color times its intensity.
        ground: The height of the fog's base.
    """
    if not fog.is_on():
        return
    var eye = Length(rays.eye.y - ground.to(METER), METER)
    # A frame has at least one pixel.
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            var direction = rays.direction(x, y)
            var distance = rays.distance(x, y, frame.depth[slot])
            var depth = fog.optical_depth(eye, direction.y, distance)
            if distance < SKY_DISTANCE:
                depth += fog.haze.to(PER_METER) * distance.to(METER)
            var keep = exp(-depth)
            var low = sky.sample(
                Vector3(direction.x, FOG_SKY_RISE, direction.z)
            )
            var tint = fog_color(low, sun, sun_light, fog, direction)
            var seen = frame.colors[slot]
            frame.colors[slot] = FloatColor(
                seen.r * keep + tint.r * (1 - keep),
                seen.g * keep + tint.g * (1 - keep),
                seen.b * keep + tint.b * (1 - keep),
                seen.a,
            )


def draw_rain(
    mut frame: RenderTarget,
    rays: ViewRays,
    rain: RainSettings,
    light: FloatColor,
    seed: Int,
):
    """Draw rain streaks over a frame.

    Each streak falls at a random pixel and a random depth from
    `RAIN_NEAR` to `RAIN_FAR` meters. A nearer streak is longer and
    brighter. A streak leans by the rain's lean, and each of its pixels is
    hidden where a surface is nearer than the streak.

    Args:
        frame: The frame, changed in place.
        rays: The camera's rays.
        rain: The rain.
        light: The light a streak catches, before its opacity.
        seed: Which streaks.
    """
    var count = rain.streaks(frame.width, frame.height)
    var random = SeededRandom(seed)
    var run = sin(rain.lean.to(RADIAN))
    var fall = cos(rain.lean.to(RADIAN))
    for _ in range(count):
        var x0 = Float32(random.next()) * Float32(frame.width)
        var y0 = Float32(random.next()) * Float32(frame.height)
        var near = Float32(random.next())
        var d = RAIN_NEAR + (RAIN_FAR - RAIN_NEAR) * near * near
        var length = RAIN_LENGTH * Float32(frame.height) * RAIN_NEAR / d * 4 + 2
        var strength = rain.opacity * (
            Float32(0.35) + Float32(0.65) * RAIN_NEAR / d
        )
        var steps = Int(length) + 1
        # A streak has at least one step.
        for k in range(steps):  # pragma: no branch
            var t = Float32(k) / Float32(steps)
            var x = Int(x0 + run * length * t)
            var y = Int(y0 + fall * length * t)
            if x < 0 or x >= frame.width or y >= frame.height:
                break
            var slot = y * frame.width + x
            if rays.distance(x, y, frame.depth[slot]).to(METER) < d:
                continue
            var fade = strength * sin(t * Float32(3.141592653589793))
            var seen = frame.colors[slot]
            frame.colors[slot] = FloatColor(
                seen.r + light.r * fade,
                seen.g + light.g * fade,
                seen.b + light.b * fade,
                seen.a,
            )


def metered_luminance(frame: RenderTarget) -> Float32:
    """Return a frame's mean luminance as an auto exposure meters it.

    The log2 luminance of every pixel falls in one of `HISTOGRAM_BINS`
    bins from `HISTOGRAM_LOW` to `HISTOGRAM_HIGH`. The darkest and the
    brightest `HISTOGRAM_TRIM` of the pixels are dropped, and the rest
    averaged in log space.

    Args:
        frame: The frame.

    Returns:
        The metered luminance, more than zero.
    """
    var bins = List[Int](length=HISTOGRAM_BINS, fill=0)
    var span = HISTOGRAM_HIGH - HISTOGRAM_LOW
    # A frame has at least one pixel.
    for color in frame.colors:  # pragma: no branch
        var level = log2(max(luminance(color), Float32(1e-6)))
        var bin = Int((level - HISTOGRAM_LOW) / span * Float32(HISTOGRAM_BINS))
        bins[min(max(bin, 0), HISTOGRAM_BINS - 1)] += 1
    var total = Float32(len(frame.colors))
    var low = total * HISTOGRAM_TRIM
    var high = total * (1 - HISTOGRAM_TRIM)
    var seen = Float32(0)
    var sum = Float32(0)
    var kept = Float32(0)
    # A constant count, more than zero.
    for b in range(HISTOGRAM_BINS):  # pragma: no branch
        var start = seen
        seen += Float32(bins[b])
        var take = max(min(seen, high) - max(start, low), 0)
        var level = (
            HISTOGRAM_LOW + (Float32(b) + 0.5) / Float32(HISTOGRAM_BINS) * span
        )
        sum += take * level
        kept += take
    return pow(Float32(2), sum / max(kept, Float32(1)))


def apply_gains(mut frame: RenderTarget, gains: FloatColor):
    """Scale every pixel's three channels.

    Args:
        frame: The frame, changed in place.
        gains: What red, green and blue are scaled by.
    """
    # A frame has at least one pixel.
    for slot in range(len(frame.colors)):  # pragma: no branch
        var seen = frame.colors[slot]
        frame.colors[slot] = FloatColor(
            seen.r * gains.r, seen.g * gains.g, seen.b * gains.b, seen.a
        )


def apply_gamma(mut frame: RenderTarget, gamma: Float32) raises:
    """Raise every tone-mapped pixel to `2.2 / gamma`.

    At a gamma of 2.2 nothing changes, since the image is then encoded
    through the sRGB curve.

    Args:
        frame: The frame, tone-mapped, changed in place.
        gamma: The camera's gamma. It must be positive.

    Raises:
        Error: If the gamma is not positive.
    """
    if not (gamma > 0):
        raise Error("A camera's gamma must be positive")
    var power = Float32(2.2) / gamma
    if power == 1:
        return
    # A frame has at least one pixel.
    for slot in range(len(frame.colors)):  # pragma: no branch
        var seen = frame.colors[slot]
        frame.colors[slot] = FloatColor(
            pow(max(seen.r, 0), power),
            pow(max(seen.g, 0), power),
            pow(max(seen.b, 0), power),
            seen.a,
        )


@fieldwise_init
struct LensSettings(ImplicitlyCopyable, Writable):
    """CARLA's lens attributes: a radial distortion and a circle falloff."""

    var k: Float32
    var kcube: Float32
    var x_size: Float32
    var y_size: Float32
    var circle_falloff: Float32
    var circle_multiplier: Float32

    def bends(self) -> Bool:
        """Return True when the distortion moves any pixel.

        Returns:
            Whether either coefficient and either size is not zero.
        """
        return (self.k != 0 or self.kcube != 0) and (
            self.x_size != 0 or self.y_size != 0
        )

    def write_to(self, mut writer: Some[Writer]):
        """Write the lens.

        Args:
            writer: The destination.
        """
        writer.write("LensSettings(k=", self.k, ", kcube=", self.kcube, ")")


def lens_source(
    lens: LensSettings, u: Float32, v: Float32
) -> Tuple[Float32, Float32]:
    """Return where a lens reads the pixel it shows at a place.

    The place is measured from the image's middle, from -1 to 1 on each
    axis, and r is its distance over the corner's. The lens reads from
    the place scaled by `(1 - (k r^2 + kcube r^3) size LENS_GAIN)` on each axis,
    over the same at the corner, so the corners read the corners. A
    negative k bends the image like a barrel.

    Args:
        lens: The lens.
        u: Across, -1 at the left and 1 at the right.
        v: Down, -1 at the top and 1 at the bottom.

    Returns:
        The place read, on the same scale.
    """
    var r = sqrt((u * u + v * v) / 2)
    var bend = lens.k * r * r + lens.kcube * r * r * r
    var corner = lens.k + lens.kcube
    var sx = lens.x_size * LENS_GAIN
    var sy = lens.y_size * LENS_GAIN
    var su = (1 - bend * sx) / (1 - corner * sx)
    var sv = (1 - bend * sy) / (1 - corner * sy)
    return (u * su, v * sv)


def lens_falloff(lens: LensSettings, u: Float32, v: Float32) -> Float32:
    """Return how much light the lens lets through at a place.

    Args:
        lens: The lens.
        u: Across, from -1 to 1.
        v: Down, from -1 to 1.

    Returns:
        `1 - multiplier * r^falloff`, held from zero to one, where r is
        the distance over the corner's.
    """
    var r = sqrt((u * u + v * v) / 2)
    return min(
        max(1 - lens.circle_multiplier * pow(r, lens.circle_falloff), 0), 1
    )


def apply_lens(mut frame: RenderTarget, lens: LensSettings):
    """Bend and darken a frame as the lens does.

    Args:
        frame: The frame, changed in place.
        lens: The lens.
    """
    var bends = lens.bends()
    if not bends and lens.circle_multiplier == 0:
        return
    var before = frame.colors.copy()
    var w = Float32(frame.width)
    var h = Float32(frame.height)
    # A frame has at least one pixel.
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var u = (Float32(x) + 0.5) / w * 2 - 1
            var v = (Float32(y) + 0.5) / h * 2 - 1
            var seen = before[y * frame.width + x]
            if bends:
                var from_ = lens_source(lens, u, v)
                seen = _bilinear(
                    before,
                    frame.width,
                    frame.height,
                    (from_[0] + 1) / 2 * w - 0.5,
                    (from_[1] + 1) / 2 * h - 0.5,
                )
            var keep = lens_falloff(lens, u, v)
            frame.colors[y * frame.width + x] = FloatColor(
                seen.r * keep, seen.g * keep, seen.b * keep, seen.a
            )


def _bilinear(
    colors: List[FloatColor], width: Int, height: Int, x: Float32, y: Float32
) -> FloatColor:
    """Return a bilinear sample of an image, held at its edges."""
    var fx = min(max(x, 0), Float32(width - 1))
    var fy = min(max(y, 0), Float32(height - 1))
    var x0 = Int(fx)
    var y0 = Int(fy)
    var x1 = min(x0 + 1, width - 1)
    var y1 = min(y0 + 1, height - 1)
    var tx = fx - Float32(x0)
    var ty = fy - Float32(y0)
    var a = colors[y0 * width + x0]
    var b = colors[y0 * width + x1]
    var c = colors[y1 * width + x0]
    var d = colors[y1 * width + x1]
    var top = FloatColor(
        a.r + (b.r - a.r) * tx,
        a.g + (b.g - a.g) * tx,
        a.b + (b.b - a.b) * tx,
        a.a + (b.a - a.a) * tx,
    )
    var bottom = FloatColor(
        c.r + (d.r - c.r) * tx,
        c.g + (d.g - c.g) * tx,
        c.b + (d.b - c.b) * tx,
        c.a + (d.a - c.a) * tx,
    )
    return FloatColor(
        top.r + (bottom.r - top.r) * ty,
        top.g + (bottom.g - top.g) * ty,
        top.b + (bottom.b - top.b) * ty,
        top.a + (bottom.a - top.a) * ty,
    )
