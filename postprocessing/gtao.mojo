# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Ground-truth ambient occlusion: three.js's `GTAOPass`, with its
`GTAOShader` and its `PoissonDenoiseShader`.

**The occlusion.** For each pixel that holds a surface, `gtao_occlusion`
cuts the hemisphere above it into three slices, or five for thirty samples
or more. In each slice it walks out both ways and keeps the highest
horizon it meets, and it integrates the visible arc against the normal.
A five by five magic square turns the slices from pixel to pixel, as
three.js's `generateMagicSquareNoise` does.

**The denoise.** `gtao_denoise` averages sixteen taps on a Poisson disk
around each pixel. Each tap weighs by how like the pixel it is: its
occlusion, its depth along the normal, and its normal. A simplex noise
texture turns the disk from pixel to pixel.

**Randomness.** three.js seeds its simplex noise from `Math.random`. This
port seeds it from `math.utils.SeededRandom`, so the same seed gives the
same frame. The magic square has no randomness.

The pass runs on the host. It reads the depth and the normals that
`postprocessing.screen_space.DepthView` reads for SSAO.
"""

from math.noise import SimplexNoise
from math.utils import SeededRandom
from math.vector3 import Vector3
from postprocessing.sampling import LightView, u_of, v_of
from postprocessing.screen_space import (
    BEAUTY_OUTPUT,
    BLUR_OUTPUT,
    DEFAULT_OUTPUT,
    DEPTH_OUTPUT,
    EFFECT_OUTPUT,
    DepthView,
    ScreenSpaceOutput,
    multiply_light,
    show_depth,
    show_normals,
    show_values,
)
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import acos, cos, floor, isfinite, pi, pow, sin, sqrt
from units.si import Length, METER

# `generateMagicSquareNoise`'s default size.
comptime GTAO_NOISE_SIZE = 5
# `GTAOPass._generateNoise`'s default size.
comptime DENOISE_NOISE_SIZE = 64
# `GTAOShader`'s `SCREEN_SPACE_RADIUS_SCALE`.
comptime SCREEN_SPACE_RADIUS_SCALE = Float32(100)
# `PoissonDenoiseShader`'s luminance weights.
comptime DENOISE_LUMA = Vector3(0.2125, 0.7154, 0.0721)


struct GtaoSettings(ImplicitlyCopyable):
    """What `GTAOPass` reads, named as three.js names it, with its
    defaults."""

    # `radius`: how far the samples reach from the surface.
    var radius: Length
    # `distanceExponent`: how the samples crowd toward the surface.
    var distance_exponent: Float32
    # `thickness`: how far in depth a sample may lie from the surface.
    var thickness: Length
    # `distanceFallOff`: how much a far sample's horizon counts less,
    # zero to one.
    var distance_fall_off: Float32
    # `scale`: the power the occlusion is raised to.
    var scale: Float32
    # `samples`: how many samples a pixel takes, over all its slices.
    var samples: Int
    # `screenSpaceRadius`: whether the radius is in pixels, per hundred.
    var screen_space_radius: Bool
    # `blendIntensity`: how much of the occlusion darkens the frame.
    var blend_intensity: Float32
    # The denoise's `lumaPhi`, `depthPhi` and `normalPhi`: how unlike a
    # tap may be and still count.
    var luma_phi: Float32
    var depth_phi: Float32
    var normal_phi: Float32
    # The denoise's `radius`, in pixels.
    var denoise_radius: Float32
    # The denoise's disk: `pdSamples` taps on `pdRings` turns, spread by
    # `pdRadiusExponent`. three.js's shader starts from an exponent of one
    # and keeps it until `updatePdMaterial` changes one of the three.
    var denoise_samples: Int
    var denoise_rings: Float32
    var denoise_radius_exponent: Float32
    # What the pass leaves in the frame: `output`.
    var output: ScreenSpaceOutput
    # The seed of the denoise's noise, where three.js calls `Math.random`.
    var seed: Int

    def __init__(out self):
        """Start with three.js's defaults."""
        self.radius = Length(0.25, METER)
        self.distance_exponent = 1
        self.thickness = Length(1.0, METER)
        self.distance_fall_off = 1
        self.scale = 1
        self.samples = 16
        self.screen_space_radius = False
        self.blend_intensity = 1
        self.luma_phi = 10
        self.depth_phi = 2
        self.normal_phi = 3
        self.denoise_radius = 8
        self.denoise_samples = 16
        self.denoise_rings = 2
        self.denoise_radius_exponent = 1
        self.output = DEFAULT_OUTPUT
        self.seed = 1


def check_gtao(settings: GtaoSettings) raises:
    """Refuse GTAO settings no pass could use.

    Args:
        settings: The settings.

    Raises:
        Error: If a setting is not finite, or the output is none of the
            six; the radius, the thickness, the scale or a phi is not
            positive; the fall-off is outside zero to one, where a horizon
            could pass straight up; the intensity or the exponent is
            negative; a sample count is below two, or the denoise's radius
            below one.
    """
    if not settings.output.is_valid():
        raise Error("A screen-space output must be one of the six named")
    if not (
        isfinite(settings.radius.value)
        and isfinite(settings.distance_exponent)
        and isfinite(settings.thickness.value)
        and isfinite(settings.distance_fall_off)
        and isfinite(settings.scale)
        and isfinite(settings.blend_intensity)
        and isfinite(settings.luma_phi)
        and isfinite(settings.depth_phi)
        and isfinite(settings.normal_phi)
        and isfinite(settings.denoise_radius)
        and isfinite(settings.denoise_rings)
        and isfinite(settings.denoise_radius_exponent)
    ):
        raise Error("A GTAO setting must be finite")
    if (
        settings.radius.value <= 0
        or settings.thickness.value <= 0
        or settings.scale <= 0
        or settings.luma_phi <= 0
        or settings.depth_phi <= 0
        or settings.normal_phi <= 0
    ):
        raise Error("A GTAO radius, thickness, scale and phi must be positive")
    if settings.distance_fall_off < 0 or settings.distance_fall_off > 1:
        raise Error("A GTAO fall-off runs from zero to one")
    if (
        settings.blend_intensity < 0
        or settings.distance_exponent < 0
        or settings.denoise_radius_exponent < 0
    ):
        raise Error("A GTAO intensity or exponent must not be negative")
    if settings.samples < 2 or settings.denoise_samples < 2:
        raise Error("A GTAO pass needs at least two samples")
    if settings.denoise_radius < 1:
        raise Error("A GTAO denoise radius is at least one pixel")


def magic_square(size: Int) -> List[Int]:
    """Return three.js's `generateMagicSquare`: the numbers one to `size`
    squared, laid out by the Siamese method, row by row. An even size is
    made the odd size above it.

    Args:
        size: The side, positive.

    Returns:
        The square's entries.
    """
    var n = size
    if n % 2 == 0:
        n += 1
    var count = n * n
    var square = List[Int](length=count, fill=0)
    var i = n // 2
    var j = n - 1
    var num = 1
    while num <= count:
        if i == -1 and j == n:
            j = n - 2
            i = 0
        else:
            if j == n:
                j = 0
            if i < 0:
                i = n - 1
        if square[i * n + j] != 0:
            j -= 2
            i += 1
            continue
        square[i * n + j] = num
        num += 1
        j += 1
        i -= 1
    return square^


def _byte(value: Float64) -> Float32:
    """Return a value stored in a `Uint8Array` and read back as a unit:
    cut to a whole byte, over 255."""
    return Float32(Int(value)) / 255


def gtao_noise(size: Int = GTAO_NOISE_SIZE) -> List[FloatColor]:
    """Return three.js's `generateMagicSquareNoise`: one unit direction in
    the plane per texel, turned by the magic square, stored in bytes.

    Args:
        size: The side, positive; an even size is made odd.

    Returns:
        The texels, row by row from the bottom, as a `DataTexture` holds
        them: the direction's x and y packed from zero to one, then 127
        and 255, over 255.
    """
    var square = magic_square(size)
    var count = len(square)
    var texels = List[FloatColor](capacity=count)
    for index in range(count):  # pragma: no branch
        var angle = 2 * pi * Float64(square[index]) / Float64(count)
        var x = cos(angle)
        var y = sin(angle)
        var length = sqrt(x * x + y * y)
        texels.append(
            FloatColor(
                _byte((x / length * 0.5 + 0.5) * 255),
                _byte((y / length * 0.5 + 0.5) * 255),
                Float32(127) / 255,
                1,
            )
        )
    return texels^


def denoise_noise(
    seed: Int, size: Int = DENOISE_NOISE_SIZE
) raises -> List[Float32]:
    """Return the red channel of `GTAOPass._generateNoise`: 2D simplex
    noise at each whole texel, packed from zero to one in a byte.

    Args:
        seed: The seed of the noise's permutation.
        size: The side.

    Returns:
        The texels, row by row from the bottom.

    Raises:
        Error: Everything `SimplexNoise.noise` raises.
    """
    var random = SeededRandom(seed)
    var simplex = SimplexNoise(random)
    var texels = List[Float32](capacity=size * size)
    for i in range(size):  # pragma: no branch
        for j in range(size):  # pragma: no branch
            var value = simplex.noise(Float64(i), Float64(j))
            texels.append(_byte((value * 0.5 + 0.5) * 255))
    return texels^


def denoise_disk(
    samples: Int, rings: Float32, radius_exponent: Float32
) -> List[Vector3]:
    """Return `generateDenoiseSamples`: `samples` directions turning
    `rings` times, each with its distance from the center, zero to one,
    raised to `radius_exponent`.

    Args:
        samples: How many, at least two.
        rings: How many turns.
        radius_exponent: How the distances crowd toward the center.

    Returns:
        The cosine and the sine of each direction, and its distance.
    """
    var disk = List[Vector3](capacity=samples)
    for i in range(samples):  # pragma: no branch
        var angle = 2 * pi * Float64(rings) * Float64(i) / Float64(samples)
        var radius = pow(
            Float64(i) / Float64(samples - 1), Float64(radius_exponent)
        )
        disk.append(
            Vector3(Float32(cos(angle)), Float32(sin(angle)), Float32(radius))
        )
    return disk^


def _unit(v: Vector3) -> Vector3:
    """Return `v` at a length of one, or zero for zero."""
    var size = v.length()
    if size == 0:
        return v
    return v * (1 / size)


def _cross(a: Vector3, b: Vector3) -> Vector3:
    """Return the cross product."""
    return Vector3(
        a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x
    )


def _row_up(y: Int, height: Int) -> Int:
    """Return a row counted up from the bottom."""
    return height - 1 - y


def _scene_sample(view: DepthView, point: Vector3) -> Vector3:
    """Return where a view-space point lands and what the frame holds
    there: `getSceneUvAndDepth`, then `getViewPosition` of the result."""
    var clip = view.projection.transform_point(point)
    var u = clip.x * 0.5 + 0.5
    var v = clip.y * 0.5 + 0.5
    return view.position(u, v, view.depth_at(u, v))


def _horizon(
    view_dir: Vector3,
    center: Vector3,
    seen: Vector3,
    horizon: Float32,
    weight: Float32,
    thickness: Float32,
) -> Float32:
    """Return one horizon raised by one sample, as `GTAOShader` raises it:
    by the part of the sample's cosine above it, times the fall-off
    weight, when the sample is within `thickness` in depth. A sample on
    the pixel's own point raises nothing: three.js normalizes a zero
    vector there."""
    var delta = seen - center
    if abs(delta.z) >= thickness or delta.length() == 0:
        return horizon
    var cosine = view_dir.dot(_unit(delta))
    return horizon + max(Float32(0), (cosine - horizon) * weight)


def gtao_occlusion(
    view: DepthView,
    normals: List[Vector3],
    noise: List[FloatColor],
    x: Int,
    y: Int,
    settings: GtaoSettings,
) -> Float32:
    """Return one pixel of `GTAOShader`: the ambient light that reaches
    it, one for none blocked.

    Args:
        view: The frame's depth.
        normals: One view-space normal per pixel.
        noise: The magic square, from `gtao_noise`.
        x: The column.
        y: The row, down from the top.
        settings: The radius, the thickness and the rest.

    Returns:
        The visibility, zero to one, raised to `scale`. A pixel with no
        surface gives one, as three.js's cleared target holds.
    """
    var slot = y * view.width + x
    var depth = view.depth[slot]
    if depth >= 1:
        return 1
    var u = u_of(x, view.width)
    var v = v_of(y, view.height)
    var center = view.position(u, v, depth)
    var normal = normals[slot]
    var radius = settings.radius.value
    if settings.screen_space_radius:
        radius *= view.position(
            0.5 + SCREEN_SPACE_RADIUS_SCALE / Float32(view.width), 0, depth
        ).x
    var side = Int(sqrt(Float32(len(noise))))
    var texel = noise[(_row_up(y, view.height) % side) * side + (x % side)]
    var tangent = _unit(Vector3(texel.r * 2 - 1, texel.g * 2 - 1, 0))
    var bitangent = Vector3(-tangent.y, tangent.x, 0)
    var reach = 0.5 + 0.5 * texel.a
    var directions = 3
    if settings.samples >= 30:
        directions = 5
    var steps = (settings.samples + directions - 1) // directions
    var view_dir = _unit(-center)
    var thickness = settings.thickness.value
    var ao = Float32(0)
    for i in range(directions):  # pragma: no branch
        var angle = Float32(i) / Float32(directions) * Float32(pi)
        var direction = _unit(tangent * cos(angle) + bitangent * sin(angle))
        var slice_bitangent = _unit(_cross(direction, view_dir))
        var slice_tangent = _cross(slice_bitangent, view_dir)
        var in_slice = _unit(
            normal - slice_bitangent * normal.dot(slice_bitangent)
        )
        var toward = _cross(in_slice, slice_bitangent)
        var cos_x = view_dir.dot(toward)
        var cos_y = view_dir.dot(-toward)
        for j in range(steps):  # pragma: no branch
            var offset = direction * (
                radius
                * reach
                * pow(
                    Float32(j + 1) / Float32(steps),
                    settings.distance_exponent,
                )
            )
            var weight = 1 + (2 / Float32(j + 2) - 1) * (
                settings.distance_fall_off
            )
            cos_x = _horizon(
                view_dir,
                center,
                _scene_sample(view, center + offset),
                cos_x,
                weight,
                thickness,
            )
            cos_y = _horizon(
                view_dir,
                center,
                _scene_sample(view, center - offset),
                cos_y,
                weight,
                thickness,
            )
        var sin_x = sqrt(1 - cos_x * cos_x)
        var sin_y = sqrt(1 - cos_y * cos_y)
        var nx = in_slice.dot(slice_tangent)
        var ny = in_slice.dot(view_dir)
        var nxb = 0.5 * (
            acos(cos_y) - acos(cos_x) + sin_x * cos_x - sin_y * cos_y
        )
        var nyb = 0.5 * (2 - cos_x * cos_x - cos_y * cos_y)
        ao += nx * nxb + ny * nyb
    ao = min(Float32(1), max(Float32(0), ao / Float32(directions)))
    return pow(ao, settings.scale)


def gtao_denoise(
    ao: LightView,
    view: DepthView,
    normals: List[Vector3],
    noise: List[Float32],
    disk: List[Vector3],
    x: Int,
    y: Int,
    settings: GtaoSettings,
) -> Float32:
    """Return one pixel of `PoissonDenoiseShader` over the occlusion.

    Args:
        ao: The occlusion, gray, one texel a pixel, read bilinear.
        view: The frame's depth.
        normals: One view-space normal per pixel.
        noise: The denoise's noise, from `denoise_noise`.
        disk: The taps, from `denoise_disk`.
        x: The column.
        y: The row, down from the top.
        settings: The phis and the radius.

    Returns:
        The denoised occlusion. A pixel with no surface, or no normal,
        gives one, as three.js's cleared target holds.
    """
    var slot = y * view.width + x
    var depth = view.depth[slot]
    var normal = normals[slot]
    if depth == 1 or normal.dot(normal) == 0:
        return 1
    var u = u_of(x, view.width)
    var v = v_of(y, view.height)
    var center = ao.sample(u, v).r
    var here = view.position(u, v, depth)
    var side = Int(sqrt(Float32(len(noise))))
    var turn = noise[(_row_up(y, view.height) % side) * side + (x % side)]
    var nx = sin(turn * 2 * Float32(pi))
    var ny = cos(turn * 2 * Float32(pi))
    var total = Float32(1)
    var denoised = center
    var center_luma = center * (
        DENOISE_LUMA.x + DENOISE_LUMA.y + DENOISE_LUMA.z
    )
    for i in range(len(disk)):  # pragma: no branch
        var tap = disk[i]
        var scale = 1 + tap.z * (settings.denoise_radius - 1)
        var ox = tap.x * scale / Float32(view.width)
        var oy = tap.y * scale / Float32(view.height)
        # `mat2(n.x, -n.y, n.x, n.y)` times the offset, column-major.
        var su = u + nx * ox + nx * oy
        var sv = v - ny * ox + ny * oy
        var neighbor = ao.sample(su, sv).r
        var sample_depth = view.depth_at(su, sv)
        var sample_normal = normals[view.slot_at(su, sv)]
        var there = view.position(su, sv, sample_depth)
        var normal_similarity = pow(
            max(normal.dot(sample_normal), Float32(0)), settings.normal_phi
        )
        var luma = neighbor * (DENOISE_LUMA.x + DENOISE_LUMA.y + DENOISE_LUMA.z)
        var luma_similarity = max(
            1 - abs(luma - center_luma) / settings.luma_phi, Float32(0)
        )
        var depth_similarity = max(
            1 - abs((here - there).dot(normal)) / settings.depth_phi,
            Float32(0),
        )
        var w = luma_similarity * depth_similarity * normal_similarity
        denoised += w * neighbor
        total += w
    return denoised / total


def gtao_light(
    mut frame: RenderTarget,
    view: DepthView,
    normals: List[Vector3],
    settings: GtaoSettings,
) raises:
    """Darken the frame by ground-truth ambient occlusion: three.js's
    `GTAOPass.render`.

    The occlusion is computed at every pixel and denoised. The default
    output scales the light by one mixed toward the denoised occlusion by
    `blend_intensity`, alpha kept, as three.js's blend with `DstColor`
    and `Zero` does.

    Args:
        frame: The frame, changed in place.
        view: The depth, drawn as the scene is.
        normals: One view-space normal per pixel: `DepthView.normals`.
        settings: The settings.

    Raises:
        Error: Everything `denoise_noise` raises.
    """
    var width = frame.width
    var height = frame.height
    var noise = gtao_noise()
    var ao = List[FloatColor](capacity=width * height)
    var values = List[Float32](capacity=width * height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var value = gtao_occlusion(view, normals, noise, x, y, settings)
            ao.append(FloatColor(value, value, value, 1))
            values.append(value)
    if settings.output == EFFECT_OUTPUT:
        show_values(frame, values)
        return
    var pd_noise = denoise_noise(settings.seed)
    var disk = denoise_disk(
        settings.denoise_samples,
        settings.denoise_rings,
        settings.denoise_radius_exponent,
    )
    var ao_view = LightView(ao, width, height)
    var denoised = List[Float32](capacity=width * height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            denoised.append(
                gtao_denoise(
                    ao_view, view, normals, pd_noise, disk, x, y, settings
                )
            )
    # The view does not keep the occlusion alive; this does.
    _ = ao^
    if settings.output == BLUR_OUTPUT:
        show_values(frame, denoised)
    elif settings.output == DEPTH_OUTPUT:
        show_depth(frame, view)
    elif settings.output == BEAUTY_OUTPUT:
        return
    elif settings.output == DEFAULT_OUTPUT:
        var factors = List[Float32](capacity=len(denoised))
        for slot in range(len(denoised)):  # pragma: no branch
            factors.append(1 + (denoised[slot] - 1) * settings.blend_intensity)
        multiply_light(frame, factors)
    else:
        # `NORMAL_OUTPUT`, the one left once `check_gtao` has had its say.
        show_normals(frame, normals)
