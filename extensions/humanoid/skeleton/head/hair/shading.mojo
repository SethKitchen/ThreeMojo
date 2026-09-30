# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Hair shading in strand space: Kajiya-Kay's diffuse and Marschner's
specular, worked out at each point of a groom.

A hair is a thin glossy cylinder, and a surface's normal means little
for it. Its shading reads the strand's tangent instead. Light scatters
off a fiber along three paths (Marschner et al. 2003, "Light Scattering
from Human Hair Fibers"):

- R: it reflects off the outside of the fiber. A white highlight,
  shifted toward the tip by the tilt of the cuticle's scales.
- TT: it passes through the fiber and out the far side, colored by the
  pigment. Bright when the light is behind the hair.
- TRT: it passes in, reflects off the far wall, and comes back out: a
  second, colored highlight shifted toward the root.

Each path is a longitudinal Gaussian times an azimuthal term, as Brian
Karis fit them for real time ("Physically Based Hair Shading in Unreal",
SIGGRAPH 2016). Light that bounces between many fibers is faked, as
Karis does too, and light lost on its way down into the hair falls off
with the depth, as the Beer-Lambert law has it.

The shade is worked out once per point, not per pixel: "strand-space
shading", as Frostbite's hair does it. The strands are then drawn unlit
in those colors. This module ports the shading of Frostbitten Hair
WebGPU by Marcin Matuszczyk, MIT license, copyright 2024. See
THIRD-PARTY-NOTICES.md.

This is not a three.js port. See Extensions.

    var colors = shade_groom(groom, HairLook(tone), lights, eye)
"""

from extensions.humanoid.skeleton.head.hair.groom import HairGroom
from math.vector3 import Vector3
from std.math import exp, log, max, min, pi, sqrt

# Human hair's index of refraction, and the Fresnel reflectance at
# normal incidence it gives.
comptime HAIR_IOR = Float32(1.55)
comptime HAIR_F0 = (1 - HAIR_IOR) * (1 - HAIR_IOR) / (
    (1 + HAIR_IOR) * (1 + HAIR_IOR)
)
comptime _SQRT_TWO_PI = Float32(2.5066282746)


@fieldwise_init
struct HairLight(ImplicitlyCopyable):
    """A distant light as the hair sees it."""

    # The unit direction toward the light.
    var direction: Vector3
    # Its color times its intensity, linear.
    var radiance: Vector3


struct HairLook(ImplicitlyCopyable):
    """How a head of hair scatters light."""

    # The fiber's color, linear, which tints TT and TRT.
    var color: Vector3
    # How strong each of Marschner's paths is.
    var specular: Float32
    var weight_tt: Float32
    var weight_trt: Float32
    # The cuticle's tilt, which shifts the highlights, and the fiber's
    # roughness, which widens them.
    var shift: Float32
    var roughness: Float32
    # How fast light fades with depth into the hair, per meter.
    var attenuation: Float32
    # The most a shadow may darken a strand, zero through one.
    var shadows: Float32

    def __init__(out self, color: Vector3):
        """Take Frostbitten's defaults for a fiber of `color`.

        Args:
            color: The fiber's linear color.
        """
        self.color = color
        self.specular = Float32(0.9)
        self.weight_tt = Float32(0.0)
        self.weight_trt = Float32(1.4)
        self.shift = Float32(0.035)
        self.roughness = Float32(0.3)
        self.attenuation = Float32(350.0)
        self.shadows = Float32(0.75)


def _times(a: Vector3, b: Vector3) -> Vector3:
    """Return `a` and `b` multiplied channel by channel."""
    return Vector3(a.x * b.x, a.y * b.y, a.z * b.z)


def _saturate(x: Float32) -> Float32:
    """Return `x` held to zero through one."""
    return min(max(x, Float32(0)), Float32(1))


def _cos_half(cos_angle: Float32) -> Float32:
    """Return the cosine of half an angle from the cosine of the whole."""
    return sqrt(_saturate(Float32(0.5) + Float32(0.5) * cos_angle))


def _fresnel(cos_theta: Float32) -> Float32:
    """Return Schlick's Fresnel reflectance for hair."""
    var m = 1 - _saturate(cos_theta)
    return HAIR_F0 + (1 - HAIR_F0) * m * m * m * m * m


def _gaussian(
    sin_i: Float32, sin_r: Float32, alpha: Float32, beta: Float32
) -> Float32:
    """Return the longitudinal Gaussian M_p (Karis 2016, page 18)."""
    var a = sin_i + sin_r - alpha
    return exp(-(a * a) / (2 * beta * beta)) / (beta * _SQRT_TWO_PI)


def _pow3(base: Vector3, exponent: Float32) -> Vector3:
    """Return each channel of `base` raised to `exponent`."""
    return Vector3(
        exp(exponent * _ln(base.x)),
        exp(exponent * _ln(base.y)),
        exp(exponent * _ln(base.z)),
    )


def _ln(x: Float32) -> Float32:
    """Return the natural logarithm of `x`, held above a tiny floor."""
    return log(max(x, Float32(1e-6)))


def marschner(
    look: HairLook, to_light: Vector3, to_camera: Vector3, tangent: Vector3
) -> Vector3:
    """Return Marschner's specular, R plus TT plus TRT, for one light.

    Args:
        look: The fiber's color and the three paths' weights.
        to_light: The unit direction toward the light.
        to_camera: The unit direction toward the camera.
        tangent: The unit direction along the strand, toward its tip.

    Returns:
        The scattered light per unit of the light's radiance, linear.
    """
    var sin_i = tangent.dot(to_light)
    var sin_r = tangent.dot(to_camera)
    var cos_i = sqrt(max(Float32(0), 1 - sin_i * sin_i))
    var cos_r = sqrt(max(Float32(0), 1 - sin_r * sin_r))
    var cos_d = _cos_half(cos_i * cos_r + sin_i * sin_r)
    var light_perp = to_light - tangent * sin_i
    var camera_perp = to_camera - tangent * sin_r
    var cos_phi = light_perp.dot(camera_perp) / sqrt(
        light_perp.length() * camera_perp.length() + Float32(1e-4)
    )
    var cos_half_phi = _cos_half(cos_phi)
    var beta2 = look.roughness * look.roughness
    # R: off the outside of the fiber.
    var m_r = _gaussian(sin_i, sin_r, -2 * look.shift, beta2)
    var n_r = Float32(0.25) * cos_half_phi * _fresnel(cos_d)
    var result = Vector3(1, 1, 1) * (look.specular * m_r * n_r)
    # TT: through the fiber.
    var m_tt = _gaussian(sin_i, sin_r, look.shift, Float32(0.5) * beta2)
    var eta = Float32(1.19) / max(cos_d, Float32(1e-3)) + Float32(0.36) * cos_d
    var a = 1 / eta
    var h_tt = (1 + a * (Float32(0.6) - Float32(0.8) * cos_phi)) * cos_half_phi
    var t_tt = _pow3(
        look.color,
        sqrt(max(Float32(0), 1 - h_tt * h_tt * a * a))
        / (2 * max(cos_d, Float32(1e-3))),
    )
    var d_tt = exp(Float32(-3.65) * cos_phi - Float32(3.98))
    var f_tt = _fresnel(cos_d * sqrt(_saturate(1 - h_tt * h_tt)))
    result = result + t_tt * (
        look.weight_tt * m_tt * (1 - f_tt) * (1 - f_tt) * d_tt
    )
    # TRT: in, off the far wall, and back out.
    var m_trt = _gaussian(sin_i, sin_r, 4 * look.shift, 2 * beta2)
    var t_trt = _pow3(look.color, Float32(0.8) / max(cos_d, Float32(1e-3)))
    var d_trt = exp(Float32(17.0) * cos_phi - Float32(16.78))
    var f_trt = _fresnel(cos_d * Float32(0.5))
    result = result + t_trt * (
        look.weight_trt * m_trt * (1 - f_trt) * (1 - f_trt) * f_trt * d_trt
    )
    return result


def kajiya_kay(color: Vector3, to_light: Vector3, tangent: Vector3) -> Vector3:
    """Return Kajiya and Kay's diffuse for one light.

    A cylinder's diffuse is the sine of the angle between the light and
    the strand. It is lifted a little, as Scheuermann's is, so the
    shadow's edge is soft.

    Args:
        color: The fiber's linear color.
        to_light: The unit direction toward the light.
        tangent: The unit direction along the strand.

    Returns:
        The diffuse per unit of the light's radiance, linear: the
        fiber's color over pi, times the sine.
    """
    var t = tangent.dot(to_light)
    var s = sqrt(max(Float32(0), 1 - t * t))
    # Over pi, as a Lambertian surface's is, so the hair is as bright
    # under a light as the skin beside it.
    return color * ((Float32(0.25) + Float32(0.75) * s) / Float32(pi))


def scattered(
    color: Vector3, to_light: Vector3, to_camera: Vector3, tangent: Vector3
) -> Vector3:
    """Return Karis's fake multiple scattering for one light.

    Light that has bounced between many fibers comes out the pigment's
    color and nearly from every way. Karis stands a normal square to the
    strand facing the camera, and lights it softly.

    Args:
        color: The fiber's linear color.
        to_light: The unit direction toward the light.
        to_camera: The unit direction toward the camera.
        tangent: The unit direction along the strand.

    Returns:
        The scattered light per unit of the light's radiance, linear.
    """
    var n = to_camera - tangent * to_camera.dot(tangent)
    var length = n.length()
    if length > Float32(1e-6):
        n = n / length
    var wrap = (_saturate(n.dot(to_light)) + 1) / Float32(4 * pi)
    return Vector3(sqrt(color.x), sqrt(color.y), sqrt(color.z)) * wrap


def shade_groom(
    groom: HairGroom,
    look: HairLook,
    lights: List[HairLight],
    camera: Vector3,
    ambient: Vector3,
) -> List[Float32]:
    """Return every point's color, linear, three floats a point.

    Args:
        groom: The strands, in the frame the lights and the camera are
            given in.
        look: How the fibers scatter light.
        lights: The distant lights.
        camera: Where the camera is.
        ambient: The light from all round, linear.

    Returns:
        Three floats per point of the groom, in its order.
    """
    var colors = List[Float32](capacity=len(groom.points) * 3)
    for strand in range(len(groom)):  # pragma: no branch
        var shade = groom.shades[strand]
        var base = look.color * shade
        var strand_look = look
        strand_look.color = base
        for index in range(
            groom.starts[strand], groom.starts[strand + 1]
        ):  # pragma: no branch
            var p = groom.points[index]
            var t = groom.tangent(index)
            var n = groom.normals[index]
            var to_camera = camera - p
            to_camera.normalize()
            # Light is lost on its way down into the hair.
            var buried = exp(-look.attenuation * groom.depths[index])
            var sum = _times(ambient, base) * buried
            for l in range(len(lights)):  # pragma: no branch
                var light = lights[l]
                # The head shades the hair on its far side; the hair
                # over a strand shades it by its depth.
                var facing = _saturate(
                    (n.dot(light.direction) + Float32(0.3)) * 2
                )
                var shadow = max(1 - look.shadows, facing * buried)
                var diffuse = kajiya_kay(base, light.direction, t) + scattered(
                    base, light.direction, to_camera, t
                )
                var specular = marschner(
                    strand_look, light.direction, to_camera, t
                )
                var lit = diffuse * shadow + specular * shadow
                sum = sum + _times(lit, light.radiance)
            colors.append(sum.x)
            colors.append(sum.y)
            colors.append(sum.z)
    return colors^


def segment_colors(groom: HairGroom, colors: List[Float32]) -> List[Float32]:
    """Return per-point colors laid out as `groom_lines` lays its points:
    each segment's two ends in turn.

    Args:
        groom: The strands the colors belong to.
        colors: Three floats per point of the groom.

    Returns:
        Three floats per end of every segment.
    """
    var laid = List[Float32]()
    for strand in range(len(groom)):  # pragma: no branch
        for index in range(
            groom.starts[strand], groom.starts[strand + 1] - 1
        ):  # pragma: no branch
            for end in range(2):  # pragma: no branch
                var i = (index + end) * 3
                laid.append(colors[i])
                laid.append(colors[i + 1])
                laid.append(colors[i + 2])
    return laid^
