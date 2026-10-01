# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Light effects of a CARLA RGB image that need no ground truth.

Each effect works on a frame the rasterizer drew, with its depth and its
normals, and on the sun's shadow maps from `Renderer.shadow_maps`. They
are well-known screen-space techniques:

- **The direct share.** A pixel's light is the sun's plus the sky's.
  `direct_share` splits it from the pixel's normal, the sun's direction,
  the sun's shadow maps and the physical sun and sky of
  `render_weather`: the sun gives `E_sun max(n . s, 0) v`, with v what the
  shadow maps let through, and the sky gives `E_sky (1 + n_y) / 2` plus
  the ground's bounce, `GROUND_ALBEDO E_ground (1 - n_y) / 2`. The share
  is the sun's part over both. The albedo is the same factor in both, so
  the split needs no albedo buffer.
- **Ambient occlusion.** Ground-truth ambient occlusion, three.js's
  `GTAOPass`, from `postprocessing.gtao`, run on the frame's own depth and
  normals rather than on a second drawing. The occlusion darkens only the
  sky's share of the light, as it does in the world: a surface in the sun
  keeps its sunlight.
- **Cloud shadows.** The sunlight on each point crosses the cloud layer
  of `render_sky.cloud_shadow_density`. Where the cloud is thicker than
  the cover's mean, the sun's share of the light dims, and where it is
  thinner, it brightens: the sun's light is `1 - CLOUD_SHADE d` of the
  clear sun, where the scene's sun is lit at the mean `1 - CLOUD_SHADE c`.
- **Light shafts.** A ray through fog scatters sunlight only where the sun
  reaches it. `fog_light_shafts` marches each ray through the sun's shadow
  maps and weighs each step by the fog's density there. The height fog
  then scatters only that share of the sunlight, so a building casts a
  dark shaft through the haze.

The constants are this port's own choices.
"""

from extensions.carla.render_post import ViewRays
from extensions.carla.render_sky import cloud_shadow_density
from extensions.carla.render_weather import CLOUD_SHADE, HeightFog
from lights.shadow import ShadowMap
from math.noise import ImprovedNoise
from math.vector3 import Vector3
from postprocessing.gtao import (
    GtaoSettings,
    check_gtao,
    denoise_disk,
    denoise_noise,
    gtao_denoise,
    gtao_noise,
    gtao_occlusion,
)
from postprocessing.sampling import LightView
from postprocessing.screen_space import DepthView
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import exp, floor, max, min
from units.si import METER, PER_METER, Length

# The ground's albedo, for the light it bounces up.
comptime GROUND_ALBEDO = Float32(0.12)
# The town's ambient occlusion: how far it reaches, how thick a surface
# is, and how many samples a pixel takes.
comptime AO_RADIUS = Length(1.2, METER)
comptime AO_THICKNESS = Length(1.5, METER)
comptime AO_SAMPLES = 12
# How far a light shaft is marched, how many steps it takes, and every
# how many pixels a ray is marched.
comptime SHAFT_REACH = Length(160, METER)
comptime SHAFT_STEPS = 16
comptime SHAFT_STRIDE = 3


@fieldwise_init
struct DaylightSplit(ImplicitlyCopyable, Writable):
    """The sun's and the sky's light, in the renderer's units."""

    # The sun's light on a surface that faces it.
    var sun: Float32
    # The sky's light on level ground.
    var sky: Float32
    # The light that falls on level ground, which it bounces up.
    var ground: Float32
    # The unit direction toward the sun.
    var direction: Vector3

    def write_to(self, mut writer: Some[Writer]):
        """Write the split.

        Args:
            writer: The destination.
        """
        writer.write(
            "DaylightSplit(sun=",
            self.sun,
            ", sky=",
            self.sky,
            ", ground=",
            self.ground,
            ")",
        )


def town_gtao() -> GtaoSettings:
    """Return the ambient occlusion settings for a town.

    Returns:
        The defaults of three.js with `AO_RADIUS`, `AO_THICKNESS` and
        `AO_SAMPLES`.
    """
    var settings = GtaoSettings()
    settings.radius = AO_RADIUS
    settings.thickness = AO_THICKNESS
    settings.samples = AO_SAMPLES
    return settings


def sun_visibility(
    maps: List[ShadowMap], point: Vector3, normal: Vector3
) -> Float32:
    """Return how much of the sun reaches a point.

    Args:
        maps: The sun's shadow maps, one per cascade.
        point: The point, in world space.
        normal: Its unit normal, for the maps' normal bias.

    Returns:
        The least any map lets through: one outside every map.
    """
    var lit = Float32(1)
    for m in maps:
        lit = min(lit, m.lit(point, normal))
    return lit


def sun_maps(maps: List[ShadowMap], lights: List[Int]) -> List[ShadowMap]:
    """Return the shadow maps of the sun's lights.

    Args:
        maps: Every map, from `Renderer.shadow_maps`.
        lights: The sun's lights, as indices in `Scene.lights`.

    Returns:
        The maps whose light is one of them.
    """
    var kept = List[ShadowMap]()
    for m in maps:
        for index in lights:
            if m.light == index:
                kept.append(m.copy())
    return kept^


def direct_share(
    normal: Vector3, visible: Float32, light: DaylightSplit
) -> Float32:
    """Return the share of a surface's light that comes straight from the
    sun.

    Args:
        normal: The surface's unit normal, in world space.
        visible: How much of the sun reaches it.
        light: The sun and the sky.

    Returns:
        `E_sun max(n . s, 0) v` over itself plus the sky's
        `E_sky (1 + n_y) / 2` and the ground's
        `GROUND_ALBEDO E_ground (1 - n_y) / 2`; zero with no light.
    """
    var s = light.direction
    var facing = max(normal.x * s.x + normal.y * s.y + normal.z * s.z, 0)
    var direct = light.sun * facing * visible
    var up = (1 + normal.y) / 2
    var ambient = light.sky * up + GROUND_ALBEDO * light.ground * (1 - up)
    var total = direct + ambient
    if total <= 0:
        return 0
    return direct / total


def _world_normal(frame: RenderTarget, rays: ViewRays, slot: Int) -> Vector3:
    """Return a pixel's unit normal in world space."""
    var n = rays.world.transform_direction(frame.normals[slot])
    n.normalize()
    return n


def direct_shares(
    frame: RenderTarget,
    rays: ViewRays,
    maps: List[ShadowMap],
    light: DaylightSplit,
) raises -> List[Float32]:
    """Return every pixel's `direct_share`.

    Args:
        frame: The frame, with its depth and normals.
        rays: The camera's rays.
        maps: The sun's shadow maps.
        light: The sun and the sky.

    Returns:
        One share per pixel; zero where the sky shows.

    Raises:
        Error: If the frame has no normal attachment.
    """
    var count = frame.width * frame.height
    if len(frame.normals) != count:
        raise Error("The direct share needs the frame's normals")
    var shares = List[Float32](capacity=count)
    # A frame has at least one pixel.
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            var depth = frame.depth[slot]
            if depth >= 1:
                shares.append(0)
                continue
            var n = _world_normal(frame, rays, slot)
            var point = rays.world_point(x, y, depth)
            shares.append(
                direct_share(n, sun_visibility(maps, point, n), light)
            )
    return shares^


def ambient_occlusion(
    frame: RenderTarget,
    view: DepthView,
    settings: GtaoSettings,
) raises -> List[Float32]:
    """Return every pixel's ambient visibility, denoised.

    `postprocessing.gtao`'s `gtao_occlusion` and `gtao_denoise`, run over
    the frame's own depth and normals.

    Args:
        frame: The frame, with its normals.
        view: The frame's depth, read through the camera that drew it.
        settings: The occlusion's settings.

    Returns:
        One value per pixel, one where nothing blocks the sky and less
        where something does.

    Raises:
        Error: If the settings are refused by `check_gtao`, the frame has
            no normals, or the denoise's noise cannot be made.
    """
    check_gtao(settings)
    var count = frame.width * frame.height
    if len(frame.normals) != count:
        raise Error("The ambient occlusion needs the frame's normals")
    var normals = view.normals()
    var noise = gtao_noise()
    var raw = List[FloatColor](capacity=count)
    # A frame has at least one pixel.
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var value = gtao_occlusion(view, normals, noise, x, y, settings)
            raw.append(FloatColor(value, value, value, 1))
    var pd_noise = denoise_noise(settings.seed)
    var disk = denoise_disk(
        settings.denoise_samples,
        settings.denoise_rings,
        settings.denoise_radius_exponent,
    )
    var raw_view = LightView(raw, frame.width, frame.height)
    var ao = List[Float32](capacity=count)
    # A frame has at least one pixel.
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            ao.append(
                gtao_denoise(
                    raw_view, view, normals, pd_noise, disk, x, y, settings
                )
            )
    # The view does not keep the occlusion alive; this does.
    _ = raw^
    return ao^


def apply_ambient_occlusion(
    mut frame: RenderTarget,
    ao: List[Float32],
    shares: List[Float32],
    strength: Float32,
) raises:
    """Darken the sky's share of every pixel's light by its occlusion.

    Args:
        frame: The frame, changed in place.
        ao: One ambient visibility per pixel.
        shares: One direct share per pixel.
        strength: How much of the occlusion counts, zero to one.

    Raises:
        Error: If a list does not have one entry per pixel, or the
            strength is outside zero to one.
    """
    var count = frame.width * frame.height
    if len(ao) != count or len(shares) != count:
        raise Error("The occlusion needs one value per pixel")
    if not (strength >= 0 and strength <= 1):
        raise Error("The occlusion's strength runs from zero to one")
    # A frame has at least one pixel.
    for slot in range(count):  # pragma: no branch
        var ambient = 1 - strength * (1 - ao[slot])
        var keep = shares[slot] + (1 - shares[slot]) * ambient
        var seen = frame.colors[slot]
        frame.colors[slot] = FloatColor(
            seen.r * keep, seen.g * keep, seen.b * keep, seen.a
        )


def cloud_shadow_gain(density: Float32, cover: Float32) -> Float32:
    """Return what the sunlight at a point is scaled by, against the mean
    sunlight the scene is lit with.

    Args:
        density: The cloud between the point and the sun, zero to one.
        cover: The share of the sky the clouds cover, zero to one.

    Returns:
        `(1 - CLOUD_SHADE density) / (1 - CLOUD_SHADE cover)`.
    """
    return (1 - CLOUD_SHADE * density) / (1 - CLOUD_SHADE * cover)


def apply_cloud_shadows(
    mut frame: RenderTarget,
    rays: ViewRays,
    shares: List[Float32],
    noise: ImprovedNoise,
    sun: Vector3,
    cover: Float32,
) raises:
    """Dim or brighten the sun's share of every pixel's light by the cloud
    between it and the sun.

    Args:
        frame: The frame, changed in place.
        rays: The camera's rays.
        shares: One direct share per pixel.
        noise: The sky's noise.
        sun: The unit direction toward the sun.
        cover: The share of the sky the clouds cover, zero to one.

    Raises:
        Error: If the shares do not have one entry per pixel, or the noise
            refuses a place.
    """
    if len(shares) != frame.width * frame.height:
        raise Error("The cloud shadows need one share per pixel")
    if cover <= 0 or sun.y <= 0:
        return
    # A frame has at least one pixel.
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            var share = shares[slot]
            if share <= 0:
                continue
            var point = rays.world_point(x, y, frame.depth[slot])
            var gain = cloud_shadow_gain(
                cloud_shadow_density(noise, point, sun, cover), cover
            )
            var keep = 1 - share + share * gain
            var seen = frame.colors[slot]
            frame.colors[slot] = FloatColor(
                seen.r * keep, seen.g * keep, seen.b * keep, seen.a
            )


def fog_density_at(fog: HeightFog, height: Length) -> Float32:
    """Return the fog's and the haze's extinction at a height.

    Args:
        fog: The fog.
        height: The height above the fog's base.

    Returns:
        `density exp(-falloff h) + haze`, per meter.
    """
    return fog.density.to(PER_METER) * exp(
        -fog.falloff.to(PER_METER) * height.to(METER)
    ) + fog.haze.to(PER_METER)


def shaft_share(
    rays: ViewRays,
    maps: List[ShadowMap],
    fog: HeightFog,
    x: Int,
    y: Int,
    depth: Float32,
    sun: Vector3,
    steps: Int,
) -> Float32:
    """Return the share of one pixel's ray, weighted by the fog, that the
    sun reaches.

    The ray is marched to the surface or to `SHAFT_REACH`, whichever is
    nearer, at `steps` steps each offset by the pixel's
    interleaved-gradient noise. Each step weighs by the fog's density
    there times the light that still reaches the camera from it.

    Args:
        rays: The camera's rays.
        maps: The sun's shadow maps.
        fog: The fog.
        x: The column.
        y: The row, down from the top.
        depth: The pixel's NDC depth.
        sun: The unit direction toward the sun, the normal each step is
            read with.
        steps: How many steps; one or more.

    Returns:
        The weighted share, zero to one; one where the fog has no density.
    """
    var reach = min(rays.distance(x, y, depth).to(METER), SHAFT_REACH.to(METER))
    var direction = rays.direction(x, y)
    var jitter = _interleaved_noise(x, y)
    var step = reach / Float32(steps)
    var weighed = Float32(0)
    var lit = Float32(0)
    var travelled = Float32(0)
    for k in range(steps):
        var t = (Float32(k) + jitter) * step
        var point = Vector3(
            rays.eye.x + direction.x * t,
            rays.eye.y + direction.y * t,
            rays.eye.z + direction.z * t,
        )
        var sigma = fog_density_at(fog, Length(point.y, METER))
        var weight = sigma * exp(-travelled)
        travelled += sigma * step
        weighed += weight
        lit += weight * sun_visibility(maps, point, sun)
    if weighed <= 0:
        return 1
    return lit / weighed


def _interleaved_noise(x: Int, y: Int) -> Float32:
    """Return Jimenez's interleaved gradient noise at a pixel, zero to
    one."""
    var v = Float32(52.9829189) * _fraction(
        Float32(0.06711056) * Float32(x) + Float32(0.00583715) * Float32(y)
    )
    return _fraction(v)


def _fraction(v: Float32) -> Float32:
    """Return the fractional part."""
    return v - floor(v)


def fog_light_shafts(
    frame: RenderTarget,
    rays: ViewRays,
    fog: HeightFog,
    maps: List[ShadowMap],
    sun: Vector3,
    stride: Int = SHAFT_STRIDE,
    steps: Int = SHAFT_STEPS,
) raises -> List[Float32]:
    """Return every pixel's `shaft_share`, marched every `stride` pixels
    and filled in between.

    Args:
        frame: The frame, with its depth.
        rays: The camera's rays.
        fog: The fog.
        maps: The sun's shadow maps.
        sun: The unit direction toward the sun.
        stride: March one ray every so many pixels each way.
        steps: How many steps a ray takes.

    Returns:
        One share per pixel.

    Raises:
        Error: If the stride or the steps are less than one.
    """
    if stride < 1 or steps < 1:
        raise Error("A light shaft's stride and steps must be one or more")
    var w = frame.width
    var h = frame.height
    var cols = (w - 1) // stride + 2
    var rows = (h - 1) // stride + 2
    var coarse = List[Float32](capacity=cols * rows)
    # A frame has at least one pixel, so there are two rows and columns.
    for r in range(rows):  # pragma: no branch
        for c in range(cols):  # pragma: no branch
            var x = min(c * stride, w - 1)
            var y = min(r * stride, h - 1)
            coarse.append(
                shaft_share(
                    rays, maps, fog, x, y, frame.depth[y * w + x], sun, steps
                )
            )
    var shares = List[Float32](capacity=w * h)
    # A frame has at least one pixel.
    for y in range(h):  # pragma: no branch
        for x in range(w):  # pragma: no branch
            var c = x // stride
            var r = y // stride
            var tx = Float32(x - c * stride) / Float32(stride)
            var ty = Float32(y - r * stride) / Float32(stride)
            var top = (
                coarse[r * cols + c]
                + (coarse[r * cols + c + 1] - coarse[r * cols + c]) * tx
            )
            var bottom = (
                coarse[(r + 1) * cols + c]
                + (coarse[(r + 1) * cols + c + 1] - coarse[(r + 1) * cols + c])
                * tx
            )
            shares.append(top + (bottom - top) * ty)
    return shares^
