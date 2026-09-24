# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Shader effects: fifteen of three.js's `examples/jsm/shaders/`, each run
over the screen as a `ShaderPass` runs it, and its `GodRaysShader` chain.

**The fifteen.** `RGBShiftShader`, `BrightnessContrastShader`,
`HueSaturationShader`, `ColorCorrectionShader`, `ColorifyShader`,
`BleachBypassShader`, `TechnicolorShader`, `SobelOperatorShader`,
`FreiChenShader`, `KaleidoShader`, `MirrorShader`,
`HorizontalTiltShiftShader`, `VerticalTiltShiftShader`, `ExposureShader`
and `GammaCorrectionShader`. `ShaderEffect` names one, and
`EffectSettings` holds the uniforms each reads, with three.js's defaults.
`effect_pixel` is one pixel of any of them, line for line with its
fragment shader.

**What each reads.** A shader reads a straight texel. The frame holds
premultiplied light, so a color transform unpremultiplies each texel, runs
the shader's arithmetic, and premultiplies the result by the alpha the
shader writes. The tilt shifts are blurs and the kaleidoscope and the
mirror move texels, so they read and write the premultiplied light, where
a sum is a sum. A tap reads the frame bilinear and clamped at the edges,
as a render target's texture reads it.

**God rays.** three.js's god-rays example chains four shaders. The depth is
drawn with a `MeshDepthMaterial` and turned into a mask,
`GodRaysDepthMaskShader`. Three passes of `GodRaysGenerateShader` blur the
mask toward the sun at a quarter of the frame's size. `GodRaysCombineShader`
adds the result to the frame. `GodRaysFakeSunShader` paints a glow behind
the scene. `god_rays_light` runs the chain.

Each effect's arithmetic for one pixel is a function the GPU backend's
kernels call as well; see `render.gpu.GpuComposer`.
"""

from math.arc_tangent import atan2_float32
from math.matrix4 import Matrix4
from math.vector3 import Vector3
from postprocessing.sampling import LightView, u_of, v_of
from postprocessing.screen_space import DepthView
from render.framebuffer import Color, FloatColor
from render.target import RenderTarget
from std.math import cos, floor, isfinite, pow, sin, sqrt
from units.si import Angle, RADIAN


@fieldwise_init
struct ShaderEffect(Equatable, ImplicitlyCopyable, Writable):
    """Which of three.js's screen shaders an effect pass runs, as a type
    rather than a bare int.

    The type stops a bare integer at compile time; it does not stop
    `ShaderEffect(15)`, which `check_effect` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the fifteen effects there are.

        Returns:
            Whether the value is zero through fourteen.
        """
        return self.value >= 0 and self.value <= 14


# `RGBShiftShader`: red and blue shifted apart.
comptime RGB_SHIFT = ShaderEffect(0)
# `BrightnessContrastShader`.
comptime BRIGHTNESS_CONTRAST = ShaderEffect(1)
# `HueSaturationShader`.
comptime HUE_SATURATION = ShaderEffect(2)
# `ColorCorrectionShader`: a power, a scale and an offset per channel.
comptime COLOR_CORRECTION = ShaderEffect(3)
# `ColorifyShader`: the luminance times a color.
comptime COLORIFY = ShaderEffect(4)
# `BleachBypassShader`: the silver kept in the print.
comptime BLEACH_BYPASS = ShaderEffect(5)
# `TechnicolorShader`: two-strip film.
comptime TECHNICOLOR = ShaderEffect(6)
# `SobelOperatorShader`: the edges of the red channel.
comptime SOBEL = ShaderEffect(7)
# `FreiChenShader`: the edges by the Frei-Chen masks.
comptime FREI_CHEN = ShaderEffect(8)
# `KaleidoShader`: the frame folded into wedges.
comptime KALEIDO = ShaderEffect(9)
# `MirrorShader`: one half of the frame mirrored onto the other.
comptime MIRROR = ShaderEffect(10)
# `HorizontalTiltShiftShader`: a blur across that grows away from a row.
comptime HORIZONTAL_TILT_SHIFT = ShaderEffect(11)
# `VerticalTiltShiftShader`: the same blur, down.
comptime VERTICAL_TILT_SHIFT = ShaderEffect(12)
# `ExposureShader`: the light scaled.
comptime EXPOSURE = ShaderEffect(13)
# `GammaCorrectionShader`: the sRGB transfer function.
comptime GAMMA_CORRECTION = ShaderEffect(14)


@fieldwise_init
struct MirrorSide(Equatable, ImplicitlyCopyable, Writable):
    """Which half of the frame `MirrorShader` keeps, as a type rather than
    a bare int: three.js's `side` uniform.

    The type stops a bare integer at compile time; it does not stop
    `MirrorSide(4)`, which `check_effect` refuses.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the four sides there are.

        Returns:
            Whether the value is zero through three.
        """
        return self.value >= 0 and self.value <= 3


# `side` 0: the left half is kept and mirrored onto the right.
comptime MIRROR_LEFT = MirrorSide(0)
# `side` 1: the right half is kept and mirrored onto the left.
comptime MIRROR_RIGHT = MirrorSide(1)
# `side` 2: the top half is kept and mirrored onto the bottom.
comptime MIRROR_TOP = MirrorSide(2)
# `side` 3: the bottom half is kept and mirrored onto the top.
comptime MIRROR_BOTTOM = MirrorSide(3)

# The weights both tilt shift shaders give their nine taps, the center
# fifth: the same as three.js's blur shaders.
comptime TILT_WEIGHTS = SIMD[DType.float32, 8](
    0.051, 0.0918, 0.12245, 0.1531, 0.1633, 0.1531, 0.12245, 0.0918
)
comptime TILT_LAST_WEIGHT = Float32(0.051)
# `KaleidoShader`'s `tau`, as the shader spells it.
comptime KALEIDO_TAU = Float32(2.0 * 3.1416)
# `HueSaturationShader`'s pi, as the shader spells it.
comptime HUE_PI = Float32(3.14159265)
# `sRGBTransferOETF`'s exponent, as three.js spells it.
comptime OETF_EXPONENT = Float32(0.41666)
# How many floats `effect_floats` packs an `EffectSettings` into.
comptime EFFECT_FLOATS = 26


struct EffectSettings(ImplicitlyCopyable):
    """What a shader effect pass reads: the effect and the uniforms of all
    fifteen shaders, named as three.js names them, with its defaults.

    An effect reads its own uniforms and leaves the others alone.
    """

    # Which shader runs.
    var effect: ShaderEffect
    # `RGBShiftShader`'s `amount`, in texture widths: 0.005.
    var amount: Float32
    # `RGBShiftShader`'s and `KaleidoShader`'s `angle`: zero.
    var angle: Angle
    # `BrightnessContrastShader`'s `brightness` and `contrast`: zero.
    var brightness: Float32
    var contrast: Float32
    # `HueSaturationShader`'s `hue` and `saturation`: zero.
    var hue: Float32
    var saturation: Float32
    # `ColorCorrectionShader`'s `powRGB` (2, 2, 2), `mulRGB` (1, 1, 1) and
    # `addRGB` (0, 0, 0).
    var pow_rgb: Vector3
    var mul_rgb: Vector3
    var add_rgb: Vector3
    # `ColorifyShader`'s `color`, in sRGB: white.
    var color: Color
    # `BleachBypassShader`'s `opacity`: one.
    var opacity: Float32
    # `KaleidoShader`'s `sides`: six.
    var sides: Float32
    # `MirrorShader`'s `side`: the right half.
    var side: MirrorSide
    # The tilt shift's `h` or `v`: how far apart its taps are, per unit of
    # distance from the focus row, in texture widths or heights: 1 / 512.
    var spread: Float32
    # The tilt shift's `r`: the texture row in focus, up from the bottom:
    # 0.35.
    var focus: Float32
    # `ExposureShader`'s `exposure`: one.
    var exposure: Float32

    def __init__(out self, effect: ShaderEffect = RGB_SHIFT):
        """Start with three.js's defaults for every uniform.

        Args:
            effect: Which shader runs.
        """
        self.effect = effect
        self.amount = 0.005
        self.angle = Angle(0.0, RADIAN)
        self.brightness = 0
        self.contrast = 0
        self.hue = 0
        self.saturation = 0
        self.pow_rgb = Vector3(2, 2, 2)
        self.mul_rgb = Vector3(1, 1, 1)
        self.add_rgb = Vector3(0, 0, 0)
        self.color = Color(255, 255, 255)
        self.opacity = 1
        self.sides = 6
        self.side = MIRROR_RIGHT
        self.spread = Float32(1.0 / 512.0)
        self.focus = 0.35
        self.exposure = 1


def _finite(v: Vector3) -> Bool:
    """Return True if every component of `v` is finite."""
    return isfinite(v.x) and isfinite(v.y) and isfinite(v.z)


def check_effect(settings: EffectSettings) raises:
    """Refuse effect settings no shader could run.

    Args:
        settings: The settings.

    Raises:
        Error: If the effect or the mirror side is none of the named ones;
            a uniform is not finite; the contrast is one or more, where
            the shader divides by zero; the saturation is above one, where
            its weight changes sign; or the sides are not positive.
    """
    if not settings.effect.is_valid():
        raise Error("A shader effect must be one of the fifteen named")
    if not settings.side.is_valid():
        raise Error("A mirror side must be one of the four named")
    var scalars = (
        isfinite(settings.amount)
        and isfinite(settings.angle.value)
        and isfinite(settings.brightness)
        and isfinite(settings.contrast)
        and isfinite(settings.hue)
        and isfinite(settings.saturation)
        and isfinite(settings.opacity)
        and isfinite(settings.sides)
        and isfinite(settings.spread)
        and isfinite(settings.focus)
        and isfinite(settings.exposure)
    )
    var vectors = (
        _finite(settings.pow_rgb)
        and _finite(settings.mul_rgb)
        and _finite(settings.add_rgb)
    )
    if not (scalars and vectors):
        raise Error("A shader effect's uniforms must be finite")
    if settings.contrast >= 1:
        raise Error("A contrast must be below one")
    if settings.saturation > 1:
        raise Error("A saturation must not be above one")
    if settings.sides <= 0:
        raise Error("A kaleidoscope needs a positive number of sides")


def effect_floats(settings: EffectSettings) -> List[Float32]:
    """Return the settings as `EFFECT_FLOATS` floats, in the order
    `effect_from_floats` reads them: how the GPU backend hands them to its
    kernel.

    Args:
        settings: The settings.

    Returns:
        The floats.
    """
    var c = settings.color
    return [
        Float32(settings.effect.value),
        settings.amount,
        settings.angle.value,
        settings.brightness,
        settings.contrast,
        settings.hue,
        settings.saturation,
        settings.pow_rgb.x,
        settings.pow_rgb.y,
        settings.pow_rgb.z,
        settings.mul_rgb.x,
        settings.mul_rgb.y,
        settings.mul_rgb.z,
        settings.add_rgb.x,
        settings.add_rgb.y,
        settings.add_rgb.z,
        Float32(c.r),
        Float32(c.g),
        Float32(c.b),
        settings.opacity,
        settings.sides,
        Float32(settings.side.value),
        settings.spread,
        settings.focus,
        settings.exposure,
        Float32(c.a),
    ]


def effect_from_floats(
    floats: MutPointer[Float32, MutAnyOrigin]
) -> EffectSettings:
    """Return the settings `effect_floats` packed.

    Args:
        floats: The first of `EFFECT_FLOATS` floats.

    Returns:
        The settings.
    """
    var settings = EffectSettings(ShaderEffect(Int(floats[unsafe_offset=0])))
    settings.amount = floats[unsafe_offset=1]
    settings.angle = Angle(floats[unsafe_offset=2], RADIAN)
    settings.brightness = floats[unsafe_offset=3]
    settings.contrast = floats[unsafe_offset=4]
    settings.hue = floats[unsafe_offset=5]
    settings.saturation = floats[unsafe_offset=6]
    settings.pow_rgb = Vector3(
        floats[unsafe_offset=7],
        floats[unsafe_offset=8],
        floats[unsafe_offset=9],
    )
    settings.mul_rgb = Vector3(
        floats[unsafe_offset=10],
        floats[unsafe_offset=11],
        floats[unsafe_offset=12],
    )
    settings.add_rgb = Vector3(
        floats[unsafe_offset=13],
        floats[unsafe_offset=14],
        floats[unsafe_offset=15],
    )
    settings.color = Color(
        UInt8(Int(floats[unsafe_offset=16])),
        UInt8(Int(floats[unsafe_offset=17])),
        UInt8(Int(floats[unsafe_offset=18])),
        UInt8(Int(floats[unsafe_offset=25])),
    )
    settings.opacity = floats[unsafe_offset=19]
    settings.sides = floats[unsafe_offset=20]
    settings.side = MirrorSide(Int(floats[unsafe_offset=21]))
    settings.spread = floats[unsafe_offset=22]
    settings.focus = floats[unsafe_offset=23]
    settings.exposure = floats[unsafe_offset=24]
    return settings


def effect_luminance(r: Float32, g: Float32, b: Float32) -> Float32:
    """Return three.js's `luminance`: rec. 709's weights on linear light.

    Args:
        r: Red.
        g: Green.
        b: Blue.

    Returns:
        The weighted sum.
    """
    return 0.2126729 * r + 0.7151522 * g + 0.0721750 * b


def _glsl_mod(x: Float32, y: Float32) -> Float32:
    """Return GLSL's `mod`: `x - y * floor(x / y)`."""
    return x - y * floor(x / y)


def _straight(source: LightView, u: Float32, v: Float32) -> FloatColor:
    """Return the straight texel at a texture coordinate."""
    return source.sample(u, v).unpremultiplied()


# --- the per-pixel shaders ----------------------------------------------------


def rgb_shift_pixel(
    source: LightView, u: Float32, v: Float32, amount: Float32, angle: Angle
) -> FloatColor:
    """Return one pixel of `RGBShiftShader`: red read `amount` along
    `angle`, blue read the other way, green and alpha read at the pixel.

    Args:
        source: The frame.
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.
        amount: How far apart, in texture widths.
        angle: Which way red moves.

    Returns:
        The light, premultiplied.
    """
    var ox = amount * cos(angle.value)
    var oy = amount * sin(angle.value)
    var cr = _straight(source, u + ox, v + oy)
    var cga = _straight(source, u, v)
    var cb = _straight(source, u - ox, v - oy)
    return FloatColor(cr.r, cga.g, cb.b, cga.a).premultiplied()


def brightness_contrast_color(
    color: FloatColor, brightness: Float32, contrast: Float32
) -> FloatColor:
    """Return one straight color through `BrightnessContrastShader`.

    Args:
        color: The straight color.
        brightness: Added to each channel, minus one to one.
        contrast: Below zero toward gray, above zero away from it.

    Returns:
        The straight color, alpha kept.
    """
    var r = color.r + brightness
    var g = color.g + brightness
    var b = color.b + brightness
    if contrast > 0:
        var k = 1 - contrast
        return FloatColor(
            (r - 0.5) / k + 0.5,
            (g - 0.5) / k + 0.5,
            (b - 0.5) / k + 0.5,
            color.a,
        )
    var k = 1 + contrast
    return FloatColor(
        (r - 0.5) * k + 0.5, (g - 0.5) * k + 0.5, (b - 0.5) * k + 0.5, color.a
    )


def hue_saturation_color(
    color: FloatColor, hue: Float32, saturation: Float32
) -> FloatColor:
    """Return one straight color through `HueSaturationShader`.

    The hue turns the color about the gray axis by `hue` times pi. The
    saturation then moves each channel toward the average, or away from
    it above zero.

    Args:
        color: The straight color.
        hue: The turn, minus one to one.
        saturation: Minus one grays, zero keeps, up to one saturates.

    Returns:
        The straight color, alpha kept.
    """
    var angle = hue * HUE_PI
    var s = sin(angle)
    var c = cos(angle)
    var root3 = sqrt(Float32(3))
    var wx = (2 * c + 1) / 3
    var wy = (-root3 * s - c + 1) / 3
    var wz = (root3 * s - c + 1) / 3
    # `dot(rgb, weights.xyz)`, `.zxy` and `.yzx`.
    var r = color.r * wx + color.g * wy + color.b * wz
    var g = color.r * wz + color.g * wx + color.b * wy
    var b = color.r * wy + color.g * wz + color.b * wx
    var average = (r + g + b) / 3
    var k = -saturation
    if saturation > 0:
        k = 1 - 1 / (Float32(1.001) - saturation)
    return FloatColor(
        r + (average - r) * k,
        g + (average - g) * k,
        b + (average - b) * k,
        color.a,
    )


def color_correction_color(
    color: FloatColor, pow_rgb: Vector3, mul_rgb: Vector3, add_rgb: Vector3
) -> FloatColor:
    """Return one straight color through `ColorCorrectionShader`:
    `mulRGB * pow(rgb + addRGB, powRGB)`.

    Args:
        color: The straight color.
        pow_rgb: The power of each channel.
        mul_rgb: The scale of each channel.
        add_rgb: The offset of each channel, added first.

    Returns:
        The straight color, alpha kept.
    """
    return FloatColor(
        mul_rgb.x * pow(color.r + add_rgb.x, pow_rgb.x),
        mul_rgb.y * pow(color.g + add_rgb.y, pow_rgb.y),
        mul_rgb.z * pow(color.b + add_rgb.z, pow_rgb.z),
        color.a,
    )


def colorify_color(color: FloatColor, tint: FloatColor) -> FloatColor:
    """Return one straight color through `ColorifyShader`: its luminance
    times the tint.

    Args:
        color: The straight color.
        tint: The linear color it is tinted with.

    Returns:
        The straight color, alpha kept.
    """
    var value = effect_luminance(color.r, color.g, color.b)
    return FloatColor(value * tint.r, value * tint.g, value * tint.b, color.a)


def _bleach(base: Float32, lum: Float32, l: Float32, a2: Float32) -> Float32:
    """Return one channel of `BleachBypassShader`."""
    var result1 = 2 * base * lum
    var result2 = 1 - 2 * (1 - lum) * (1 - base)
    var new_color = result1 + (result2 - result1) * l
    return a2 * new_color + (1 - a2) * base


def bleach_bypass_color(color: FloatColor, opacity: Float32) -> FloatColor:
    """Return one straight color through `BleachBypassShader`.

    The color is overlaid with its own luminance: multiplied below a
    luminance of 0.45 and screened from 0.55 up, blended between. The
    result is mixed in by the opacity times the alpha.

    Args:
        color: The straight color.
        opacity: How much of the bleach shows.

    Returns:
        The straight color, alpha kept.
    """
    var lum = effect_luminance(color.r, color.g, color.b)
    var l = min(Float32(1), max(Float32(0), 10 * (lum - 0.45)))
    var a2 = opacity * color.a
    return FloatColor(
        _bleach(color.r, lum, l, a2),
        _bleach(color.g, lum, l, a2),
        _bleach(color.b, lum, l, a2),
        color.a,
    )


def technicolor_color(color: FloatColor) -> FloatColor:
    """Return one straight color through `TechnicolorShader`: red kept,
    green and blue both their average, and opaque.

    Args:
        color: The straight color.

    Returns:
        The straight color, alpha one.
    """
    var cyan = (color.g + color.b) * 0.5
    return FloatColor(color.r, cyan, cyan, 1)


def exposure_color(color: FloatColor, exposure: Float32) -> FloatColor:
    """Return one straight color through `ExposureShader`.

    Args:
        color: The straight color.
        exposure: What red, green and blue are scaled by.

    Returns:
        The straight color, alpha kept.
    """
    return FloatColor(
        color.r * exposure, color.g * exposure, color.b * exposure, color.a
    )


def _oetf(value: Float32) -> Float32:
    """Return one channel of three.js's `sRGBTransferOETF`, with its own
    exponent."""
    if value <= 0.0031308:
        return value * 12.92
    return pow(value, OETF_EXPONENT) * 1.055 - 0.055


def gamma_correction_color(color: FloatColor) -> FloatColor:
    """Return one straight color through `GammaCorrectionShader`: three.js's
    `sRGBTransferOETF` on red, green and blue.

    Args:
        color: The straight color.

    Returns:
        The encoded color, alpha kept.
    """
    return FloatColor(_oetf(color.r), _oetf(color.g), _oetf(color.b), color.a)


def _texel_red(source: LightView, u: Float32, v: Float32) -> Float32:
    """Return the straight red of a texel."""
    return _straight(source, u, v).r


def sobel_pixel(source: LightView, u: Float32, v: Float32) -> FloatColor:
    """Return one pixel of `SobelOperatorShader`: the length of the red
    channel's gradient over the three by three texels around the pixel.

    Args:
        source: The frame.
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.

    Returns:
        The gradient as opaque gray.
    """
    var du = 1 / Float32(source.width)
    var dv = 1 / Float32(source.height)
    # `tx{c}y{r}`: the texel `c - 1` across and `r - 1` up.
    var t00 = _texel_red(source, u - du, v - dv)
    var t01 = _texel_red(source, u - du, v)
    var t02 = _texel_red(source, u - du, v + dv)
    var t10 = _texel_red(source, u, v - dv)
    var t12 = _texel_red(source, u, v + dv)
    var t20 = _texel_red(source, u + du, v - dv)
    var t21 = _texel_red(source, u + du, v)
    var t22 = _texel_red(source, u + du, v + dv)
    # `Gx` and `Gy`, column-major, with their zero entries left out.
    var gx = -t00 - 2 * t01 - t02 + t20 + 2 * t21 + t22
    var gy = -t00 + t02 - 2 * t10 + 2 * t12 - t20 + t22
    var g = sqrt(gx * gx + gy * gy)
    return FloatColor(g, g, g, 1)


# `FreiChenShader`'s nine masks, `g0` through `g8`, each column-major: the
# entry `c * 3 + r` weighs the texel `c - 1` across and `r - 1` up.
comptime _FREI_CHEN = SIMD[DType.float32, 128](
    0.3535533845424652,
    0,
    -0.3535533845424652,
    0.5,
    0,
    -0.5,
    0.3535533845424652,
    0,
    -0.3535533845424652,
    0.3535533845424652,
    0.5,
    0.3535533845424652,
    0,
    0,
    0,
    -0.3535533845424652,
    -0.5,
    -0.3535533845424652,
    0,
    0.3535533845424652,
    -0.5,
    -0.3535533845424652,
    0,
    0.3535533845424652,
    0.5,
    -0.3535533845424652,
    0,
    0.5,
    -0.3535533845424652,
    0,
    -0.3535533845424652,
    0,
    0.3535533845424652,
    0,
    0.3535533845424652,
    -0.5,
    0,
    -0.5,
    0,
    0.5,
    0,
    0.5,
    0,
    -0.5,
    0,
    -0.5,
    0,
    0.5,
    0,
    0,
    0,
    0.5,
    0,
    -0.5,
    0.1666666716337204,
    -0.3333333432674408,
    0.1666666716337204,
    -0.3333333432674408,
    0.6666666865348816,
    -0.3333333432674408,
    0.1666666716337204,
    -0.3333333432674408,
    0.1666666716337204,
    -0.3333333432674408,
    0.1666666716337204,
    -0.3333333432674408,
    0.1666666716337204,
    0.6666666865348816,
    0.1666666716337204,
    -0.3333333432674408,
    0.1666666716337204,
    -0.3333333432674408,
    0.3333333432674408,
    0.3333333432674408,
    0.3333333432674408,
    0.3333333432674408,
    0.3333333432674408,
    0.3333333432674408,
    0.3333333432674408,
    0.3333333432674408,
    0.3333333432674408,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
)


def frei_chen_mask(mask: Int, column: Int, row: Int) -> Float32:
    """Return one entry of one of `FreiChenShader`'s nine masks.

    Args:
        mask: Which mask, zero through eight.
        column: Its column, zero through two: the texel `column - 1`
            across.
        row: Its row, zero through two: the texel `row - 1` up.

    Returns:
        The weight.
    """
    return _FREI_CHEN[mask * 9 + column * 3 + row]


def frei_chen_pixel(source: LightView, u: Float32, v: Float32) -> FloatColor:
    """Return one pixel of `FreiChenShader`.

    Each texel of the three by three around the pixel weighs the length of
    its straight red, green and blue. Each mask weighs those nine, and the
    square of the result is its response. The edge is the square root of
    the first four responses over all nine.

    Args:
        source: The frame.
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.

    Returns:
        The edge as opaque gray. Where every response is zero, three.js
        divides zero by zero; this gives black.
    """
    var du = 1 / Float32(source.width)
    var dv = 1 / Float32(source.height)
    var intensity = SIMD[DType.float32, 16](0)
    for column in range(3):  # pragma: no branch
        for row in range(3):  # pragma: no branch
            var t = _straight(
                source,
                u + du * Float32(column - 1),
                v + dv * Float32(row - 1),
            )
            intensity[column * 3 + row] = sqrt(
                t.r * t.r + t.g * t.g + t.b * t.b
            )
    var cnv = SIMD[DType.float32, 16](0)
    for mask in range(9):  # pragma: no branch
        var dp3 = Float32(0)
        for entry in range(9):  # pragma: no branch
            dp3 += _FREI_CHEN[mask * 9 + entry] * intensity[entry]
        cnv[mask] = dp3 * dp3
    var m = (cnv[0] + cnv[1]) + (cnv[2] + cnv[3])
    var s = (cnv[4] + cnv[5]) + (cnv[6] + cnv[7]) + (cnv[8] + m)
    var edge = Float32(0)
    if s > 0:
        edge = sqrt(m / s)
    return FloatColor(edge, edge, edge, 1)


def kaleido_pixel(
    source: LightView, u: Float32, v: Float32, sides: Float32, angle: Angle
) -> FloatColor:
    """Return one pixel of `KaleidoShader`: the frame folded into `sides`
    mirrored wedges about its center.

    Args:
        source: The frame.
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.
        sides: How many wedges.
        angle: How far the wedges are turned.

    Returns:
        The texel the fold lands on, premultiplied.
    """
    var px = u - 0.5
    var py = v - 0.5
    var r = sqrt(px * px + py * py)
    var a = atan2_float32(py, px) + angle.value
    var wedge = KALEIDO_TAU / sides
    a = _glsl_mod(a, wedge)
    a = abs(a - wedge / 2)
    return source.sample(r * cos(a) + 0.5, r * sin(a) + 0.5)


def mirror_pixel(
    source: LightView, u: Float32, v: Float32, side: MirrorSide
) -> FloatColor:
    """Return one pixel of `MirrorShader`.

    Args:
        source: The frame.
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.
        side: Which half is kept.

    Returns:
        The texel, premultiplied.
    """
    var px = u
    var py = v
    if side == MIRROR_LEFT:
        if px > 0.5:
            px = 1 - px
    elif side == MIRROR_RIGHT:
        if px < 0.5:
            px = 1 - px
    elif side == MIRROR_TOP:
        if py < 0.5:
            py = 1 - py
    else:
        if py > 0.5:
            py = 1 - py
    return source.sample(px, py)


def tilt_shift_pixel(
    source: LightView,
    u: Float32,
    v: Float32,
    spread: Float32,
    focus: Float32,
    across: Bool,
) -> FloatColor:
    """Return one pixel of `HorizontalTiltShiftShader`, or of
    `VerticalTiltShiftShader` when not `across`.

    Nine taps with three.js's blur weights, apart by `spread` times the
    distance of the pixel's row from the focus row. Both shaders measure
    that distance along `vUv.y`, as three.js's do.

    Args:
        source: The frame.
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.
        spread: The shader's `h` or `v`.
        focus: The shader's `r`.
        across: Whether the taps run along the row.

    Returns:
        The weighted sum of the taps, premultiplied.
    """
    var step = spread * abs(focus - v)
    var sum = FloatColor(0, 0, 0, 0)
    var tap = 0
    while tap < 9:
        var weight = TILT_LAST_WEIGHT
        if tap < 8:
            weight = TILT_WEIGHTS[tap]
        var offset = Float32(tap - 4) * step
        var tu = u
        var tv = v + offset
        if across:
            tu = u + offset
            tv = v
        var here = source.sample(tu, tv)
        sum = FloatColor(
            sum.r + here.r * weight,
            sum.g + here.g * weight,
            sum.b + here.b * weight,
            sum.a + here.a * weight,
        )
        tap += 1
    return sum


def effect_color(color: FloatColor, settings: EffectSettings) -> FloatColor:
    """Return one straight color through an effect that reads nothing but
    its own texel.

    Args:
        color: The straight color.
        settings: The effect, one of the eight color transforms.

    Returns:
        The straight color the shader writes.
    """
    var effect = settings.effect
    if effect == BRIGHTNESS_CONTRAST:
        return brightness_contrast_color(
            color, settings.brightness, settings.contrast
        )
    if effect == HUE_SATURATION:
        return hue_saturation_color(color, settings.hue, settings.saturation)
    if effect == COLOR_CORRECTION:
        return color_correction_color(
            color, settings.pow_rgb, settings.mul_rgb, settings.add_rgb
        )
    if effect == COLORIFY:
        return colorify_color(color, FloatColor(srgb=settings.color))
    if effect == BLEACH_BYPASS:
        return bleach_bypass_color(color, settings.opacity)
    if effect == TECHNICOLOR:
        return technicolor_color(color)
    if effect == EXPOSURE:
        return exposure_color(color, settings.exposure)
    # `GAMMA_CORRECTION`, the last color transform.
    return gamma_correction_color(color)


def reads_neighbors(effect: ShaderEffect) -> Bool:
    """Return True if an effect reads texels other than its own pixel's.

    Args:
        effect: The effect.

    Returns:
        Whether it does: the shift, the two edge filters, the kaleidoscope,
        the mirror and the two tilt shifts.
    """
    return (
        effect == RGB_SHIFT
        or effect == SOBEL
        or effect == FREI_CHEN
        or effect == KALEIDO
        or effect == MIRROR
        or effect == HORIZONTAL_TILT_SHIFT
        or effect == VERTICAL_TILT_SHIFT
    )


def effect_pixel(
    source: LightView, x: Int, y: Int, settings: EffectSettings
) -> FloatColor:
    """Return one pixel of a shader effect: what both backends run.

    Args:
        source: The frame before the pass, premultiplied.
        x: The column.
        y: The row, down from the top.
        settings: The effect and its uniforms.

    Returns:
        The light the shader writes, premultiplied.
    """
    var u = u_of(x, source.width)
    var v = v_of(y, source.height)
    var effect = settings.effect
    if effect == RGB_SHIFT:
        return rgb_shift_pixel(source, u, v, settings.amount, settings.angle)
    if effect == SOBEL:
        return sobel_pixel(source, u, v)
    if effect == FREI_CHEN:
        return frei_chen_pixel(source, u, v)
    if effect == KALEIDO:
        return kaleido_pixel(source, u, v, settings.sides, settings.angle)
    if effect == MIRROR:
        return mirror_pixel(source, u, v, settings.side)
    if effect == HORIZONTAL_TILT_SHIFT:
        return tilt_shift_pixel(
            source, u, v, settings.spread, settings.focus, True
        )
    if effect == VERTICAL_TILT_SHIFT:
        return tilt_shift_pixel(
            source, u, v, settings.spread, settings.focus, False
        )
    var straight = source.at(x, y).unpremultiplied()
    return effect_color(straight, settings).premultiplied()


def effect_light(mut frame: RenderTarget, settings: EffectSettings):
    """Run a shader effect over the frame, as `ShaderPass` runs the shader.

    Every pixel reads the frame as it was before the pass. The result
    holds light.

    Args:
        frame: The frame, changed in place.
        settings: The effect and its uniforms.
    """
    var width = frame.width
    var height = frame.height
    var source = frame.colors.copy()
    var view = LightView(source, width, height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            var slot = y * width + x
            frame.colors[slot] = effect_pixel(view, x, y, settings)
            frame.data[slot] = False
            x += 1
        y += 1
    # The view does not keep the copy alive; this does.
    _ = source^


# --- god rays -----------------------------------------------------------------

# `GodRaysGenerateShader`'s `TAPS_PER_PASS`.
comptime GOD_RAYS_TAPS = 6
# How many generate passes three.js's example runs.
comptime GOD_RAYS_PASSES = 3
# `GodRaysGenerateShader` fades the rays in as the sun's clip z reaches
# this.
comptime GOD_RAYS_FADE_DEPTH = Float32(1000)
# `GodRaysFakeSunShader`'s glow reaches this far, in frame heights.
comptime GOD_RAYS_SUN_REACH = Float32(0.5)
# ...and is this bright at its center.
comptime GOD_RAYS_SUN_PEAK = Float32(0.35)


struct GodRaysSettings(ImplicitlyCopyable):
    """What three.js's god-rays chain reads, named as its example and its
    shaders name it, with their defaults."""

    # Where the sun is, in the world: the example's `sunPosition`.
    var sun: Vector3
    # `fGodRayIntensity`: how much the rays add: 0.69.
    var intensity: Float32
    # The example's `filterLen`: how far the rays reach, in texture
    # widths: one.
    var filter_length: Float32
    # The example's `godrayRenderTargetResolutionMultiplier`: the rays'
    # size as a fraction of the frame's: a quarter.
    var resolution_scale: Float32
    # Whether to paint `GodRaysFakeSunShader`'s glow behind the scene.
    var fake_sun: Bool
    # The glow's `sunColor` and `bgColor`, in sRGB: 0xffee00 and black.
    var sun_color: Color
    var bg_color: Color

    def __init__(out self, sun: Vector3 = Vector3(0, 1000, -1000)):
        """Start with three.js's defaults.

        Args:
            sun: Where the sun is, in the world. The default is the
                example's.
        """
        self.sun = sun
        self.intensity = 0.69
        self.filter_length = 1.0
        self.resolution_scale = 0.25
        self.fake_sun = False
        self.sun_color = Color(255, 238, 0)
        self.bg_color = Color(0, 0, 0)


def check_god_rays(settings: GodRaysSettings) raises:
    """Refuse god-ray settings no chain could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a setting is not finite; the intensity is negative; the
            filter length is not positive; or the resolution scale is not
            above zero and at most one.
    """
    if not (
        _finite(settings.sun)
        and isfinite(settings.intensity)
        and isfinite(settings.filter_length)
        and isfinite(settings.resolution_scale)
    ):
        raise Error("A god-ray setting must be finite")
    if settings.intensity < 0:
        raise Error("A god-ray intensity must not be negative")
    if settings.filter_length <= 0:
        raise Error("A god-ray filter length must be positive")
    if settings.resolution_scale <= 0 or settings.resolution_scale > 1:
        raise Error("A god-ray resolution scale runs above zero to one")


def god_rays_size(size: Int, scale: Float32) -> Int:
    """Return the rays' width or height: the frame's times the scale, cut
    to a whole number as WebGL cuts a target's size, and at least one.

    Args:
        size: The frame's width or height.
        scale: The resolution scale.

    Returns:
        The size in pixels.
    """
    return max(1, Int(Float32(size) * scale))


def god_rays_step(filter_length: Float32, index: Int) -> Float32:
    """Return one generate pass's step: the example's `getStepSize`,
    `filterLen * TAPS_PER_PASS^-pass`.

    Args:
        filter_length: How far the rays reach.
        index: The pass, one through three.

    Returns:
        The step, in texture widths.
    """
    return filter_length * pow(Float32(GOD_RAYS_TAPS), Float32(-index))


def god_rays_sun(projection_view: Matrix4, sun: Vector3) -> Vector3:
    """Return the sun as the example hands it to the shaders: its texture
    coordinate across and up, and its clip-space z.

    The example divides x and y by the clip w and keeps z as it is, for
    the shaders' test of whether the sun is in front.

    Args:
        projection_view: The camera's projection times its view.
        sun: The sun, in the world.

    Returns:
        The texture coordinate in x and y, and the clip z.
    """
    ref e = projection_view.elements
    var x = e[0] * sun.x + e[4] * sun.y + e[8] * sun.z + e[12]
    var y = e[1] * sun.x + e[5] * sun.y + e[9] * sun.z + e[13]
    var z = e[2] * sun.x + e[6] * sun.y + e[10] * sun.z + e[14]
    var w = e[3] * sun.x + e[7] * sun.y + e[11] * sun.z + e[15]
    return Vector3((x / w + 1) / 2, (y / w + 1) / 2, z)


def god_rays_generate_pixel(
    source: LightView, u: Float32, v: Float32, sun: Vector3, step: Float32
) -> FloatColor:
    """Return one pixel of `GodRaysGenerateShader`: six taps of the red
    channel walked from the pixel toward the sun, each `step` apart,
    summed and divided by six.

    A tap past the sun, or at or above the top of the texture, adds
    nothing. The taps fade in as the sun's clip z reaches a thousand.

    Args:
        source: The mask or the last pass's rays.
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.
        sun: The sun's texture coordinate and clip z; see `god_rays_sun`.
        step: The pass's step, from `god_rays_step`.

    Returns:
        The rays as opaque gray. At the sun itself three.js divides zero
        by zero; this walks nowhere, and only the first tap counts, as
        only it is within `iters` of zero.
    """
    var dx = sun.x - u
    var dy = sun.y - v
    var dist = sqrt(dx * dx + dy * dy)
    var sx = Float32(0)
    var sy = Float32(0)
    if dist > 0:
        sx = step * dx / dist
        sy = step * dy / dist
    var iters = dist / step
    var f = min(Float32(1), max(sun.z / GOD_RAYS_FADE_DEPTH, Float32(0)))
    var tu = u
    var tv = v
    var col = Float32(0)
    for tap in range(GOD_RAYS_TAPS):  # pragma: no branch
        if Float32(tap) <= iters and tv < 1:
            col += source.sample(tu, tv).r * f
        tu += sx
        tv += sy
    var value = col / Float32(GOD_RAYS_TAPS)
    return FloatColor(value, value, value, 1)


def fake_sun_color(
    u: Float32,
    v: Float32,
    aspect: Float32,
    sun: Vector3,
    sun_color: FloatColor,
    bg_color: FloatColor,
) -> FloatColor:
    """Return one pixel of `GodRaysFakeSunShader`: a glow about the sun,
    fading to the background color half a frame height away.

    Args:
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.
        aspect: The frame's width over its height: `fAspect`.
        sun: The sun's texture coordinate and clip z.
        sun_color: The glow's linear color.
        bg_color: The background's linear color.

    Returns:
        The straight color, opaque. A sun behind the camera gives the
        background color.
    """
    if sun.z <= 0:
        return FloatColor(bg_color.r, bg_color.g, bg_color.b, 1)
    var dx = (u - sun.x) * aspect
    var dy = v - sun.y
    var prop = min(
        Float32(1),
        max(Float32(0), sqrt(dx * dx + dy * dy) / GOD_RAYS_SUN_REACH),
    )
    var k = 1 - prop
    prop = GOD_RAYS_SUN_PEAK * k * k * k
    var t = 1 - prop
    return FloatColor(
        sun_color.r + (bg_color.r - sun_color.r) * t,
        sun_color.g + (bg_color.g - sun_color.g) * t,
        sun_color.b + (bg_color.b - sun_color.b) * t,
        1,
    )


def god_rays_combine_pixel(
    color: FloatColor,
    rays: Float32,
    depth: Float32,
    u: Float32,
    v: Float32,
    aspect: Float32,
    sun: Vector3,
    settings: GodRaysSettings,
) -> FloatColor:
    """Return one pixel of `GodRaysCombineShader`, over the fake sun when
    it is asked for.

    The combine adds the intensity times one minus the rays to every
    channel of the straight color and makes it opaque. The fake sun
    replaces the background where nothing was drawn, as the example draws
    it before the scene.

    Args:
        color: The pixel's light, premultiplied.
        rays: The rays' red at the pixel.
        depth: The pixel's window depth, one where nothing was drawn.
        u: The pixel's texture coordinate across.
        v: The pixel's texture coordinate up.
        aspect: The frame's width over its height.
        sun: The sun's texture coordinate and clip z.
        settings: The intensity and the fake sun.

    Returns:
        The light, opaque.
    """
    var base = color.unpremultiplied()
    if settings.fake_sun and depth >= 1:
        base = fake_sun_color(
            u,
            v,
            aspect,
            sun,
            FloatColor(srgb=settings.sun_color),
            FloatColor(srgb=settings.bg_color),
        )
    var add = settings.intensity * (1 - rays)
    return FloatColor(base.r + add, base.g + add, base.b + add, 1)


def god_rays_mask(view: DepthView) -> List[FloatColor]:
    """Return `GodRaysDepthMaskShader` of the depth a `MeshDepthMaterial`
    draws: one minus one minus the window depth, which is the window
    depth, gray.

    three.js's depth target is cleared to black where nothing is drawn,
    so the mask is one there.

    Args:
        view: The frame's depth.

    Returns:
        The mask, one texel a pixel, row by row from the top.
    """
    var mask = List[FloatColor](capacity=len(view.depth))
    for slot in range(len(view.depth)):  # pragma: no branch
        var z = view.depth[slot]
        mask.append(FloatColor(z, z, z, 1))
    return mask^


def _generate(
    source: List[FloatColor],
    source_width: Int,
    source_height: Int,
    width: Int,
    height: Int,
    sun: Vector3,
    step: Float32,
) -> List[FloatColor]:
    """Return one generate pass into a `width` by `height` target."""
    var view = LightView(source, source_width, source_height)
    var out = List[FloatColor](capacity=width * height)
    var y = 0
    while y < height:
        var x = 0
        while x < width:
            out.append(
                god_rays_generate_pixel(
                    view, u_of(x, width), v_of(y, height), sun, step
                )
            )
            x += 1
        y += 1
    return out^


def god_rays(
    view: DepthView, sun: Vector3, settings: GodRaysSettings
) -> List[FloatColor]:
    """Return the rays: the mask blurred toward the sun by three generate
    passes, each a sixth of the step of the one before, at the rays' size.

    Args:
        view: The frame's depth.
        sun: The sun's texture coordinate and clip z.
        settings: The filter length and the resolution scale.

    Returns:
        The rays, row by row from the top, `god_rays_size` of the frame's
        width by its height.
    """
    var width = god_rays_size(view.width, settings.resolution_scale)
    var height = god_rays_size(view.height, settings.resolution_scale)
    var rays = _generate(
        god_rays_mask(view),
        view.width,
        view.height,
        width,
        height,
        sun,
        god_rays_step(settings.filter_length, 1),
    )
    for index in range(2, GOD_RAYS_PASSES + 1):  # pragma: no branch
        rays = _generate(
            rays,
            width,
            height,
            width,
            height,
            sun,
            god_rays_step(settings.filter_length, index),
        )
    return rays^


def god_rays_light(
    mut frame: RenderTarget,
    view: DepthView,
    sun: Vector3,
    settings: GodRaysSettings,
):
    """Lay god rays over the frame: three.js's god-rays example after its
    scene is drawn.

    Args:
        frame: The frame, changed in place.
        view: The frame's depth, drawn as the scene is.
        sun: The sun's texture coordinate and clip z; see `god_rays_sun`.
        settings: The intensity, the reach and the fake sun.
    """
    var rays = god_rays(view, sun, settings)
    var rays_view = LightView(
        rays,
        god_rays_size(frame.width, settings.resolution_scale),
        god_rays_size(frame.height, settings.resolution_scale),
    )
    var aspect = Float32(frame.width) / Float32(frame.height)
    var y = 0
    while y < frame.height:
        var x = 0
        while x < frame.width:
            var slot = y * frame.width + x
            var u = u_of(x, frame.width)
            var v = v_of(y, frame.height)
            frame.colors[slot] = god_rays_combine_pixel(
                frame.colors[slot],
                rays_view.sample(u, v).r,
                view.depth[slot],
                u,
                v,
                aspect,
                sun,
                settings,
            )
            frame.data[slot] = False
            x += 1
        y += 1
    # The view does not keep the rays alive; this does.
    _ = rays^
