# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sky of a picture: a gradient, the glow of the sun, and cumulus.

The renderer lights the scene from Preetham's daylight model. This module
paints what the camera sees of the sky itself, into a finished picture, where
the renderer drew nothing but the clear ground. The color is a gradient from
the pale horizon to the deep zenith, with the glow of the sun round its
direction, and cumulus over it.

The clouds are a field of noise on a flat layer above the ground. A pixel
looks along a ray. The ray meets the layer at a distance that grows toward
the horizon, so the clouds crowd and shrink toward the horizon as clouds do.
The side of a cloud toward the sun is white and the side away from it is
gray. The farther a cloud is, the paler and thinner it is.
"""

from cameras.camera import Camera
from render.framebuffer import Framebuffer
from std.math import asin, exp, floor, pi, sqrt


def _hash(x: Int, y: Int, seed: Int) -> Float64:
    """Return a repeatable number from 0 up to 1 for a lattice point."""
    var h = (
        UInt32((x * 73856093) & 0xFFFFFFFF)
        ^ UInt32((y * 19349663) & 0xFFFFFFFF)
        ^ UInt32((seed * 83492791) & 0xFFFFFFFF)
    )
    h = (h ^ (h >> 16)) * UInt32(0x45D9F3B)
    h = (h ^ (h >> 16)) * UInt32(0x45D9F3B)
    h = h ^ (h >> 16)
    return Float64(h) / 4294967296.0


def _smooth(x: Float64) -> Float64:
    """Return the smooth step of a number clamped to 0 through 1."""
    var t = min(max(x, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _noise(x: Float64, y: Float64, seed: Int) -> Float64:
    """Return value noise from 0 to 1 at a point of the plane."""
    var ix = Int(floor(x))
    var iy = Int(floor(y))
    var sx = _smooth(x - Float64(ix))
    var sy = _smooth(y - Float64(iy))
    var low = _hash(ix, iy, seed) * (1.0 - sx) + _hash(ix + 1, iy, seed) * sx
    var high = (
        _hash(ix, iy + 1, seed) * (1.0 - sx) + _hash(ix + 1, iy + 1, seed) * sx
    )
    return low * (1.0 - sy) + high * sy


def _fbm(x: Float64, y: Float64, seed: Int) -> Float64:
    """Return fractal noise from 0 to 1 at a point of the plane."""
    var total = Float64(0)
    var amplitude = Float64(0.5)
    var weight = Float64(0)
    var scale = Float64(1)
    for octave in range(6):
        total += amplitude * _noise(x * scale, y * scale, seed + 13 * octave)
        weight += amplitude
        amplitude *= 0.5
        scale *= 2.0
    return total / weight


def cloud_at(
    east: Float64,
    north: Float64,
    up: Float64,
    coverage: Float64,
    seed: Int,
    sun_east: Float64,
    sun_north: Float64,
) -> Tuple[Float64, Float64, Float64, Float64]:
    """Return the cloud that lies along a ray, as a color and an opacity.

    Args:
        east: The east component of the ray.
        north: The north component.
        up: The component upward. The ray must point above the horizon.
        coverage: How much of the sky the clouds cover, from 0 to 1.
        seed: Where the random numbers start.
        sun_east: The east component of the direction toward the sun, over
            the ground. Only its direction matters.
        sun_north: The north component.

    Returns:
        The red, green and blue, each from 0 to 255, and the opacity from 0
        to 1. The opacity is 0 in the clear sky.
    """
    var heading = sqrt(sun_east * sun_east + sun_north * sun_north)
    var toward_x = 0.0
    var toward_y = 0.0
    if heading > 1e-9:
        toward_x = sun_east / heading
        toward_y = sun_north / heading
    var threshold = 0.62 - 0.22 * coverage
    # The ray meets a flat layer of cloud at a distance that goes as the
    # cotangent of its elevation. The lowest 2 degrees of sky stay clear.
    var run = sqrt(east * east + north * north)
    var elevation_tan = up / max(run, 1e-9)
    if elevation_tan < 0.035:
        return (0.0, 0.0, 0.0, 0.0)
    var reach = 1.0 / elevation_tan
    var px = east / max(run, 1e-9) * reach * 0.55 + 40.0
    var py = north / max(run, 1e-9) * reach * 0.55 + 40.0
    var density = _fbm(px * 0.6, py * 0.6, seed)
    var body = _smooth((density - threshold) / 0.14)
    if body <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    # The side toward the sun is lit: compare the density a little toward the
    # sun with the density here.
    var lean = _fbm(
        (px + toward_x * 0.35) * 0.6, (py + toward_y * 0.35) * 0.6, seed
    )
    var lit = _smooth(0.55 + (density - lean) * 9.0)
    var shade = 0.66 + 0.34 * lit
    var depth = _smooth((density - threshold) / 0.3)
    shade *= 0.82 + 0.18 * (1.0 - 0.5 * depth)
    # The distance blues the clouds and thins them toward the horizon.
    var haze = _smooth(reach / 26.0)
    var alpha = body * (1.0 - 0.85 * haze)
    var r = 255.0 * shade * (1.0 - 0.2 * haze) + 190.0 * 0.2 * haze
    var g = 252.0 * shade * (1.0 - 0.2 * haze) + 208.0 * 0.2 * haze
    var b = 248.0 * shade * (1.0 - 0.2 * haze) + 226.0 * 0.2 * haze
    return (min(r, 255.0), min(g, 255.0), min(b, 255.0), min(alpha, 1.0))


def sky_color(
    elevation: Float64, glow: Float64
) -> Tuple[Float64, Float64, Float64]:
    """Return the color of the clear sky along a ray, in sRGB bytes.

    Args:
        elevation: The angle of the ray over the horizon, in radians.
        glow: How much of the light of the sun reaches the ray, from 0 to 1.

    Returns:
        The red, green and blue, each from 0 to 255.
    """
    var t = min(max(elevation / (pi / 2.0), 0.0), 1.0)
    var low = _smooth(t / 0.38)
    var high = _smooth((t - 0.38) / 0.62)
    # The horizon is pale, the middle of the sky blue, the zenith deep.
    var r = 198.0 * (1.0 - low) + 112.0 * low
    var g = 216.0 * (1.0 - low) + 162.0 * low
    var b = 232.0 * (1.0 - low) + 224.0 * low
    r = r * (1.0 - high) + 64.0 * high
    g = g * (1.0 - high) + 118.0 * high
    b = b * (1.0 - high) + 204.0 * high
    r += 255.0 * glow * 0.9
    g += 236.0 * glow * 0.8
    b += 200.0 * glow * 0.6
    return (min(r, 255.0), min(g, 255.0), min(b, 255.0))


def paint_sky[
    C: Camera
](
    mut image: Framebuffer,
    camera: C,
    coverage: Float64,
    seed: Int,
    sun_x: Float64,
    sun_y: Float64,
    sun_z: Float64,
) raises -> Int:
    """Paint the sky into the pixels of a picture where nothing but the sky
    was drawn.

    A pixel with no finite depth is a sky pixel.

    Args:
        image: The picture, with its depth. It is changed.
        camera: The perspective camera that drew it. It must be centered.
        coverage: How much of the sky the clouds cover, from 0 to 1.
        seed: Where the random numbers of the clouds start.
        sun_x: The east component of the direction toward the sun, with y up
            and z toward the south. The direction must be a unit vector.
        sun_y: The component upward.
        sun_z: The component toward the south.

    Returns:
        How many pixels were painted.

    Raises:
        Error: If the camera's view raises.
    """
    var width = image.width
    var height = image.height
    var world = camera.view_matrix()
    world.invert()
    var projection = camera.projection_matrix()
    var tan_x = 1.0 / Float64(projection.get(0, 0))
    var tan_y = 1.0 / Float64(projection.get(1, 1))
    var right_x = Float64(world.get(0, 0))
    var right_y = Float64(world.get(1, 0))
    var right_z = Float64(world.get(2, 0))
    var up_x = Float64(world.get(0, 1))
    var up_y = Float64(world.get(1, 1))
    var up_z = Float64(world.get(2, 1))
    var back_x = Float64(world.get(0, 2))
    var back_y = Float64(world.get(1, 2))
    var back_z = Float64(world.get(2, 2))
    var painted = 0
    for row in range(height):
        var ndc_y = 1.0 - (Float64(row) + 0.5) / Float64(height) * 2.0
        for column in range(width):
            var at = row * width + column
            if image.depth[at] < 1.0e30:
                continue
            var ndc_x = (Float64(column) + 0.5) / Float64(width) * 2.0 - 1.0
            var dx = right_x * ndc_x * tan_x + up_x * ndc_y * tan_y - back_x
            var dy = right_y * ndc_x * tan_x + up_y * ndc_y * tan_y - back_y
            var dz = right_z * ndc_x * tan_x + up_z * ndc_y * tan_y - back_z
            var length = sqrt(dx * dx + dy * dy + dz * dz)
            dx /= length
            dy /= length
            dz /= length
            var cosine = dx * sun_x + dy * sun_y + dz * sun_z
            var glow = 0.55 * exp((cosine - 1.0) * 70.0) + 0.16 * exp(
                (cosine - 1.0) * 5.0
            )
            var color = sky_color(asin(min(max(dy, 0.0), 1.0)), glow)
            var r = color[0]
            var g = color[1]
            var b = color[2]
            # The frame is y up, and z points south.
            var cloud = cloud_at(dx, -dz, dy, coverage, seed, sun_x, -sun_z)
            var alpha = cloud[3]
            r = r * (1.0 - alpha) + cloud[0] * alpha
            g = g * (1.0 - alpha) + cloud[1] * alpha
            b = b * (1.0 - alpha) + cloud[2] * alpha
            var base = at * 4
            image.pixels[base] = UInt8(Int(min(r, 255.0)))
            image.pixels[base + 1] = UInt8(Int(min(g, 255.0)))
            image.pixels[base + 2] = UInt8(Int(min(b, 255.0)))
            painted += 1
    return painted
