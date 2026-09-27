# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Edge-aware denoising of the frame: three.js r186's `DenoiseNode`, from
`examples/jsm/tsl/display/DenoiseNode.js`.

Each pixel that holds a surface averages sixteen taps on a disk around it,
the disk turned by a noise texture. Each tap weighs by how like the pixel
it is: its luminance, its depth along the pixel's normal, and its normal.
The frame's normal attachment gives the normals.

**Two things the node does that the WebGL shader does not.** The node's
texture coordinate grows down the image, so its disk is the WebGL
`PoissonDenoiseShader`'s turned upside down. And it reads the noise's
first channel as the sine's angle itself, where the shader takes that
times two pi: the node's `element( index.mod( 4 ).mul( 2 ).mul( PI ) )`
picks the channel with the whole product. Both are ported as the node
has them.

**Randomness.** three.js seeds its simplex noise from `Math.random`. This
port seeds it from `math.utils.SeededRandom`; see `postprocessing.gtao`.
"""

from math.vector3 import Vector3
from postprocessing.display_nodes import luminance_of
from postprocessing.gtao import denoise_disk, denoise_noise
from postprocessing.sampling import LightView, u_of, v_of
from postprocessing.screen_space import DepthView
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import cos, isfinite, max, pow, sin


# `generateDenoiseSamples( 16, 2, 1 )`: the disk's taps, turns and spread.
comptime DENOISE_TAPS = 16
comptime DENOISE_TURNS = Float32(2)
comptime DENOISE_SPREAD = Float32(1)


struct DenoiseSettings(ImplicitlyCopyable):
    """What a denoise pass reads, named as three.js names its uniforms,
    with its defaults."""

    # `lumaPhi`, `depthPhi` and `normalPhi`: how unlike the pixel a tap may
    # be in each way before it weighs nothing.
    var luma_phi: Float32
    var depth_phi: Float32
    var normal_phi: Float32
    # `radius`: how far the outermost tap is, in pixels.
    var radius: Float32
    # The seed of the noise, where three.js calls `Math.random`.
    var seed: Int

    def __init__(out self):
        """Start with three.js's defaults."""
        self.luma_phi = 5
        self.depth_phi = 5
        self.normal_phi = 5
        self.radius = 5
        self.seed = 1


def check_denoise(settings: DenoiseSettings) raises:
    """Refuse settings no denoise pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a phi is not a positive finite number, or the radius is
            not finite.
    """
    if not (
        isfinite(settings.luma_phi)
        and isfinite(settings.depth_phi)
        and isfinite(settings.normal_phi)
        and settings.luma_phi > 0
        and settings.depth_phi > 0
        and settings.normal_phi > 0
    ):
        raise Error("A denoise pass's phis must be positive")
    if not isfinite(settings.radius):
        raise Error("A denoise pass's radius must be finite")


def denoise_pixel(
    source: LightView,
    view: DepthView,
    normals: LightView,
    noise: List[Float32],
    disk: List[Vector3],
    x: Int,
    y: Int,
    settings: DenoiseSettings,
) -> FloatColor:
    """Return one pixel of three.js's `DenoiseNode`.

    Args:
        source: The frame, straight.
        view: The frame's depth.
        normals: The frame's view-space normals, one a pixel in red, green
            and blue, read bilinear and made unit length.
        noise: The noise, from `postprocessing.gtao.denoise_noise`.
        disk: The taps, from `postprocessing.gtao.denoise_disk`.
        x: The column.
        y: The row, down from the top.
        settings: The phis and the radius.

    Returns:
        The denoised color, straight, with the pixel's own alpha. A pixel
        with no surface, or no normal, keeps its color.
    """
    var u = u_of(x, view.width)
    var v = v_of(y, view.height)
    var depth = view.depth_at(u, v)
    var normal = _normal(normals, u, v)
    var texel = source.sample(u, v)
    if depth >= 1 or normal.dot(normal) == 0:
        return texel
    var center = luminance_of(texel.r, texel.g, texel.b)
    var here = view.position(u, v, depth)
    var side = 64
    var turn = noise[((view.height - 1 - y) % side) * side + (x % side)]
    var nx = sin(turn)
    var ny = cos(turn)
    var total = Float32(1)
    var r = texel.r
    var g = texel.g
    var b = texel.b
    # Sixteen taps, fixed.
    for i in range(len(disk)):  # pragma: no branch
        var tap = disk[i]
        var scale = 1 + tap.z * (settings.radius - 1)
        var ox = tap.x * scale / Float32(view.width)
        var oy = tap.y * scale / Float32(view.height)
        # `mat2(n.x, -n.y, n.x, n.y)` times the offset, column-major, on
        # a texture coordinate that grows down.
        var su = u + nx * ox + nx * oy
        var sv = v + ny * ox - ny * oy
        var neighbor = source.sample(su, sv)
        var there = view.position(su, sv, view.depth_at(su, sv))
        var normal_similarity = pow(
            max(normal.dot(_normal(normals, su, sv)), Float32(0)),
            settings.normal_phi,
        )
        var luma_similarity = max(
            1
            - abs(luminance_of(neighbor.r, neighbor.g, neighbor.b) - center)
            / settings.luma_phi,
            Float32(0),
        )
        var depth_similarity = max(
            1 - abs((here - there).dot(normal)) / settings.depth_phi,
            Float32(0),
        )
        var w = luma_similarity * depth_similarity * normal_similarity
        r += neighbor.r * w
        g += neighbor.g * w
        b += neighbor.b * w
        total += w
    return FloatColor(r / total, g / total, b / total, texel.a)


def _normal(normals: LightView, u: Float32, v: Float32) -> Vector3:
    """Return the normal at a texture coordinate, bilinear, made unit
    length: `normalNode.sample( uv ).rgb.normalize()`."""
    var tap = normals.sample(u, v)
    var n = Vector3(tap.r, tap.g, tap.b)
    var size = n.length()
    if size == 0:
        return n
    return n * (1 / size)


def denoise_light(
    mut frame: RenderTarget, view: DepthView, settings: DenoiseSettings
) raises:
    """Run `DenoiseNode` over the frame, every pixel reading the frame as
    it was before the pass.

    Args:
        frame: The frame, replaced. It must have a normal attachment.
        view: The frame's depth.
        settings: The denoise's settings.

    Raises:
        Error: If the frame has no normal attachment, or the noise cannot
            be made.
    """
    if not frame.has_normals():
        raise Error("A denoise pass reads the frame's normal attachment")
    var straight = List[FloatColor](capacity=len(frame.colors))
    var turned = List[FloatColor](capacity=len(frame.colors))
    # The frame has pixels, so the loop runs.
    for slot in range(len(frame.colors)):  # pragma: no branch
        straight.append(frame.straight_at(slot))
        var n = frame.normals[slot]
        turned.append(FloatColor(n.x, n.y, n.z, 0))
    var noise = denoise_noise(settings.seed)
    var disk = denoise_disk(DENOISE_TAPS, DENOISE_TURNS, DENOISE_SPREAD)
    var source = LightView(straight, frame.width, frame.height)
    var normals = LightView(turned, frame.width, frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            frame.colors[slot] = denoise_pixel(
                source, view, normals, noise, disk, x, y, settings
            ).premultiplied()
            frame.data[slot] = False
    _ = straight^
    _ = turned^
