# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Post-processing from three.js's TSL display nodes, run as composer
passes: `GaussianBlurNode`, `boxBlur`, `hashBlur`,
`ChromaticAberrationNode`, `AnamorphicNode` and `LensflareNode`, and
`Bayer`'s `bayer16`.

**What each reads.** A node reads a texture three.js keeps straight. The
frame holds premultiplied light, so a node that reads straight color
unpremultiplies each tap and premultiplies what it writes. The three
blurs take three.js's `premultipliedAlpha` option: on, they blur the
premultiplied light as it is, which is what three.js's option does to a
straight texture.

**What each writes.** A blur and the chromatic aberration replace the
frame, as a node set as the composer's output does. The anamorphic streak
and the lens flare are added to the frame, as three.js's examples add
them to the scene pass. A node that renders into a smaller target,
three.js's `resolutionScale` and `downSampleRatio`, is worked out at that
size and read back bilinear at the frame's.
"""

from postprocessing.sampling import LightView, u_of, v_of
from postprocessing.screen_space import glsl_rand
from render.framebuffer import FloatColor
from render.target import RenderTarget
from std.math import cos, floor, isfinite, pi, pow, sin, sqrt


# --- the settings ------------------------------------------------------------


struct DisplaySettings(ImplicitlyCopyable):
    """What the display node passes read, named as three.js names their
    parameters, with its defaults.

    Each pass reads its own settings and leaves the others alone.
    """

    # `gaussianBlur`'s `sigma`, its direction, which multiplies each pass's
    # step, and its `resolutionScale`.
    var sigma: Float32
    var direction_x: Float32
    var direction_y: Float32
    var resolution_scale: Float32
    # Whether a blur blurs premultiplied light, `premultipliedAlpha`.
    var premultiplied_alpha: Bool
    # `boxBlur`'s `size` and `separation`, in taps and pixels.
    var size: Int
    var separation: Int
    # `hashBlur`'s `bluramount` and `repeats`.
    var blur_amount: Float32
    var repeats: Int
    # `chromaticAberration`'s `strength`, `center` and `scale`.
    var strength: Float32
    var center_u: Float32
    var center_v: Float32
    var scale: Float32
    # `anamorphic`'s `threshold`, `scale` and `samples`, and its
    # `resolutionScale`, which is `resolution_scale`.
    var threshold: Float32
    var anamorphic_scale: Float32
    var samples: Int
    # `lensflare`'s `ghostTint`, `threshold`, `ghostSamples`,
    # `ghostSpacing`, `ghostAttenuationFactor` and `downSampleRatio`.
    var ghost_tint_r: Float32
    var ghost_tint_g: Float32
    var ghost_tint_b: Float32
    var flare_threshold: Float32
    var ghost_samples: Int
    var ghost_spacing: Float32
    var ghost_attenuation: Float32
    var down_sample_ratio: Float32

    def __init__(out self):
        """Start with three.js's defaults."""
        self.sigma = 4
        self.direction_x = 1
        self.direction_y = 1
        self.resolution_scale = 1
        self.premultiplied_alpha = False
        self.size = 1
        self.separation = 1
        self.blur_amount = 0.1
        self.repeats = 45
        self.strength = 1
        self.center_u = 0.5
        self.center_v = 0.5
        self.scale = 1.1
        self.threshold = 0.9
        self.anamorphic_scale = 3
        self.samples = 32
        self.ghost_tint_r = 1
        self.ghost_tint_g = 1
        self.ghost_tint_b = 1
        self.flare_threshold = 0.5
        self.ghost_samples = 4
        self.ghost_spacing = 0.25
        self.ghost_attenuation = 25
        self.down_sample_ratio = 4


def check_display(settings: DisplaySettings) raises:
    """Refuse settings no display pass could run.

    Args:
        settings: The settings.

    Raises:
        Error: If a number is not finite; the sigma is negative; the
            resolution scale or the down sample ratio is not positive; a
            size, a separation, a repeat count, a sample count or a ghost
            count is below what each needs.
    """
    var finite = (
        isfinite(settings.sigma)
        and isfinite(settings.direction_x)
        and isfinite(settings.direction_y)
        and isfinite(settings.resolution_scale)
        and isfinite(settings.blur_amount)
        and isfinite(settings.strength)
        and isfinite(settings.center_u)
        and isfinite(settings.center_v)
        and isfinite(settings.scale)
        and isfinite(settings.threshold)
        and isfinite(settings.anamorphic_scale)
        and isfinite(settings.ghost_tint_r)
        and isfinite(settings.ghost_tint_g)
        and isfinite(settings.ghost_tint_b)
        and isfinite(settings.flare_threshold)
        and isfinite(settings.ghost_spacing)
        and isfinite(settings.ghost_attenuation)
        and isfinite(settings.down_sample_ratio)
    )
    if not finite:
        raise Error("A display pass setting must be finite")
    if settings.sigma < 0:
        raise Error("A Gaussian blur's sigma must not be negative")
    if not (settings.resolution_scale > 0 and settings.down_sample_ratio > 0):
        raise Error("A display pass's scale and ratio must be positive")
    if settings.size < 0 or settings.separation < 0:
        raise Error("A box blur's size and separation must not be negative")
    if settings.repeats < 1 or settings.samples < 2:
        raise Error("A hash blur needs a repeat, an anamorphic two samples")
    if settings.ghost_samples < 0:
        raise Error("A lens flare's ghost count must not be negative")


# --- reading a frame ---------------------------------------------------------


def _tap(
    source: LightView, u: Float32, v: Float32, premultiplied: Bool
) -> FloatColor:
    """Return a tap as a blur reads it: the premultiplied light, or the
    straight color three.js's texture holds."""
    var color = source.sample(u, v)
    if premultiplied:
        return color
    return color.unpremultiplied()


def _stored(color: FloatColor, premultiplied: Bool) -> FloatColor:
    """Return what a blur wrote as the frame holds it, premultiplied."""
    if premultiplied:
        return color
    return color.premultiplied()


def _add(a: FloatColor, b: FloatColor, weight: Float32) -> FloatColor:
    """Return `a` plus `b` times `weight`, every channel."""
    return FloatColor(
        a.r + b.r * weight,
        a.g + b.g * weight,
        a.b + b.b * weight,
        a.a + b.a * weight,
    )


def scaled_size(size: Int, scale: Float32) -> Int:
    """Return a target's side at a resolution scale, three.js's
    `Math.max( Math.round( size * scale ), 1 )`.

    Args:
        size: The frame's side, in pixels.
        scale: The scale.

    Returns:
        The side, at least one.
    """
    return max(Int(floor(Float32(size) * scale + 0.5)), 1)


def _read_back(
    small: List[FloatColor], width: Int, height: Int, frame: RenderTarget
) -> List[FloatColor]:
    """Return a smaller target read bilinear at every pixel of the frame,
    as a pass texture is read at the frame's texture coordinates."""
    var view = LightView(small, width, height)
    var out = List[FloatColor](capacity=frame.width * frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            out.append(view.sample(u_of(x, frame.width), v_of(y, frame.height)))
    return out^


# --- GaussianBlurNode --------------------------------------------------------


def gaussian_coefficients(sigma: Float32) -> List[Float32]:
    """Return `GaussianBlurNode`'s weights: `3 + 2 * sigma` of them, of a
    Gaussian of a third of that, not normalized, as three.js leaves them.

    Args:
        sigma: The node's `sigma`.

    Returns:
        The center weight, then one per step out.
    """
    var kernel_size = 3 + 2 * sigma
    var spread = kernel_size / 3
    var out = List[Float32]()
    var i = 0
    while Float32(i) < kernel_size:
        var x = Float32(i)
        out.append(0.39894 * exp_f(-0.5 * x * x / (spread * spread)) / spread)
        i += 1
    return out^


def exp_f(x: Float32) -> Float32:
    """Return `e` to the `x`, in `Float32`."""
    return pow(Float32(2.718281828459045), x)


def _gaussian_along(
    source: LightView,
    width: Int,
    height: Int,
    weights: List[Float32],
    step_u: Float32,
    step_v: Float32,
    premultiplied: Bool,
) -> List[FloatColor]:
    """Return one of `GaussianBlurNode`'s two passes over a target of
    `width` by `height`, reading `source` a step apart each way."""
    var out = List[FloatColor](capacity=width * height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var u = u_of(x, width)
            var v = v_of(y, height)
            var sum = _tap(source, u, v, premultiplied)
            sum = FloatColor(
                sum.r * weights[0],
                sum.g * weights[0],
                sum.b * weights[0],
                sum.a * weights[0],
            )
            for i in range(1, len(weights)):  # pragma: no branch
                var du = step_u * Float32(i)
                var dv = step_v * Float32(i)
                var ahead = _tap(source, u + du, v + dv, premultiplied)
                var behind = _tap(source, u - du, v - dv, premultiplied)
                sum = _add(sum, ahead, weights[i])
                sum = _add(sum, behind, weights[i])
            # The first pass writes what the second reads; both read and
            # write as the node's `sampleTexture` and `output` do.
            out.append(sum)
    return out^


def gaussian_blur_light(mut frame: RenderTarget, settings: DisplaySettings):
    """Blur the frame across and then down, three.js's `GaussianBlurNode`,
    at its resolution scale, and read the result back at the frame's size.

    Args:
        frame: The frame, replaced.
        settings: The sigma, the direction, the resolution scale and
            whether the blur is premultiplied.
    """
    var width = scaled_size(frame.width, settings.resolution_scale)
    var height = scaled_size(frame.height, settings.resolution_scale)
    var weights = gaussian_coefficients(settings.sigma)
    var premultiplied = settings.premultiplied_alpha
    var source = frame.colors.copy()
    var across = _gaussian_along(
        LightView(source, frame.width, frame.height),
        width,
        height,
        weights,
        settings.direction_x / Float32(width),
        0,
        premultiplied,
    )
    # The second pass reads the first as it wrote it: what `output` gave,
    # straight or premultiplied as the option says.
    var down = _gaussian_along(
        LightView(across, width, height),
        width,
        height,
        weights,
        0,
        settings.direction_y / Float32(height),
        True,
    )
    var shown = _read_back(down, width, height, frame)
    for slot in range(len(frame.colors)):  # pragma: no branch
        frame.colors[slot] = _stored(shown[slot], premultiplied)
        frame.data[slot] = False
    _ = source^
    _ = across^


# --- boxBlur and hashBlur ----------------------------------------------------


def box_blur_pixel(
    source: LightView, x: Int, y: Int, settings: DisplaySettings
) -> FloatColor:
    """Return one pixel of three.js's `boxBlur`: the mean of a square of
    taps `2 * size + 1` across, `separation` pixels apart.

    Args:
        source: The frame.
        x: The column.
        y: The row, down from the top.
        settings: The size, the separation and whether the blur is
            premultiplied.

    Returns:
        The mean, as the frame holds it.
    """
    var u = u_of(x, source.width)
    var v = v_of(y, source.height)
    var sep = Float32(max(settings.separation, 1))
    var step_u = 1 / Float32(source.width) * sep
    var step_v = 1 / Float32(source.height) * sep
    var sum = FloatColor(0, 0, 0, 0)
    var count = 0
    for i in range(-settings.size, settings.size + 1):  # pragma: no branch
        for j in range(-settings.size, settings.size + 1):  # pragma: no branch
            var tap = _tap(
                source,
                u + Float32(i) * step_u,
                v + Float32(j) * step_v,
                settings.premultiplied_alpha,
            )
            sum = _add(sum, tap, 1)
            count += 1
    var share = 1 / Float32(count)
    return _stored(
        FloatColor(sum.r * share, sum.g * share, sum.b * share, sum.a * share),
        settings.premultiplied_alpha,
    )


def hash_blur_pixel(
    source: LightView, x: Int, y: Int, settings: DisplaySettings
) -> FloatColor:
    """Return one pixel of three.js's `hashBlur`: `repeats` taps round a
    circle, each at a distance three.js's `rand` sets.

    Args:
        source: The frame.
        x: The column.
        y: The row, down from the top.
        settings: The blur amount, the repeats and whether the blur is
            premultiplied.

    Returns:
        The mean, as the frame holds it.
    """
    var u = u_of(x, source.width)
    var v = v_of(y, source.height)
    var repeats = Float32(settings.repeats)
    var amount = settings.blur_amount
    var sum = FloatColor(0, 0, 0, 0)
    for step in range(settings.repeats):  # pragma: no branch
        var i = Float32(step)
        # three.js's `degrees( i / repeats * 360 )`: the loop's angle, in
        # degrees, taken by `cos` and `sin` as radians, as the node has it.
        var turn = i / repeats * 360 * 180 / Float32(pi)
        var reach = glsl_rand(i, u + v) + amount
        var qx = cos(turn) * reach
        var qy = sin(turn) * reach
        var tap = _tap(
            source,
            u + qx * amount,
            v + qy * amount,
            settings.premultiplied_alpha,
        )
        sum = _add(sum, tap, 1)
    var share = 1 / repeats
    return _stored(
        FloatColor(sum.r * share, sum.g * share, sum.b * share, sum.a * share),
        settings.premultiplied_alpha,
    )


def box_blur_light(mut frame: RenderTarget, settings: DisplaySettings):
    """Run `boxBlur` over the frame, every pixel reading the frame as it
    was before the pass.

    Args:
        frame: The frame, replaced.
        settings: The box blur's settings.
    """
    var before = frame.colors.copy()
    var view = LightView(before, frame.width, frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            frame.colors[slot] = box_blur_pixel(view, x, y, settings)
            frame.data[slot] = False
    _ = before^


def hash_blur_light(mut frame: RenderTarget, settings: DisplaySettings):
    """Run `hashBlur` over the frame, every pixel reading the frame as it
    was before the pass.

    Args:
        frame: The frame, replaced.
        settings: The hash blur's settings.
    """
    var before = frame.colors.copy()
    var view = LightView(before, frame.width, frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            frame.colors[slot] = hash_blur_pixel(view, x, y, settings)
            frame.data[slot] = False
    _ = before^


# --- ChromaticAberrationNode -------------------------------------------------


def chromatic_aberration_pixel(
    source: LightView, x: Int, y: Int, settings: DisplaySettings
) -> FloatColor:
    """Return one pixel of three.js's `ChromaticAberrationNode`: red read
    further out from the center, blue further in, green where it is.

    Args:
        source: The frame.
        x: The column.
        y: The row, down from the top.
        settings: The strength, the center and the scale.

    Returns:
        The pixel, as the frame holds it.
    """
    var u = u_of(x, source.width)
    var v = v_of(y, source.height)
    var du = u - settings.center_u
    var dv = v - settings.center_v
    var distance = sqrt(du * du + dv * dv)
    var push = settings.scale * 0.02 * settings.strength
    var aberration = settings.strength * distance
    var red_scale = 1 + push
    var blue_scale = 1 - push
    var r = (
        source.sample(
            settings.center_u + du * red_scale + du * aberration * 0.01,
            settings.center_v + dv * red_scale + dv * aberration * 0.01,
        )
        .unpremultiplied()
        .r
    )
    var g = source.sample(u, v).unpremultiplied().g
    var b = (
        source.sample(
            settings.center_u + du * blue_scale - du * aberration * 0.01,
            settings.center_v + dv * blue_scale - dv * aberration * 0.01,
        )
        .unpremultiplied()
        .b
    )
    var a = source.sample(u, v).a
    return FloatColor(r, g, b, a).premultiplied()


def chromatic_aberration_light(
    mut frame: RenderTarget, settings: DisplaySettings
):
    """Run `ChromaticAberrationNode` over the frame, every pixel reading
    the frame as it was before the pass.

    Args:
        frame: The frame, replaced.
        settings: The strength, the center and the scale.
    """
    var before = frame.colors.copy()
    var view = LightView(before, frame.width, frame.height)
    for y in range(frame.height):  # pragma: no branch
        for x in range(frame.width):  # pragma: no branch
            var slot = y * frame.width + x
            frame.colors[slot] = chromatic_aberration_pixel(
                view, x, y, settings
            )
            frame.data[slot] = False
    _ = before^


# --- AnamorphicNode ----------------------------------------------------------

# `AnamorphicNode`'s `colorNode`: the streak's tint.
comptime ANAMORPHIC_TINT_R = Float32(0.1)
comptime ANAMORPHIC_TINT_G = Float32(0.0)
comptime ANAMORPHIC_TINT_B = Float32(1.0)


def luminance_of(r: Float32, g: Float32, b: Float32) -> Float32:
    """Return three.js's `luminance`, rec. 709's weights."""
    return 0.2126729 * r + 0.7151522 * g + 0.0721750 * b


def anamorphic_light(mut frame: RenderTarget, settings: DisplaySettings):
    """Add three.js's `AnamorphicNode` to the frame: the light above a
    luminance threshold, smeared along the row and tinted blue, at the
    node's resolution scale.

    The taps run from minus half the samples to one less than half, each
    `scale` of the frame's pixels apart, weighted by one less its share of
    half, as three.js's loop runs them.

    Args:
        frame: The frame, changed in place.
        settings: The threshold, the scale, the samples and the resolution
            scale.
    """
    var width = scaled_size(frame.width, settings.resolution_scale)
    var height = scaled_size(frame.height, settings.resolution_scale)
    var before = frame.colors.copy()
    var view = LightView(before, frame.width, frame.height)
    var half = settings.samples // 2
    var inv_x = 1 / Float32(frame.width)
    var streak = List[FloatColor](capacity=width * height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var u = u_of(x, width)
            var v = v_of(y, height)
            var r = Float32(0)
            var g = Float32(0)
            var b = Float32(0)
            for i in range(-half, half):  # pragma: no branch
                var softness = 1 - abs(Float32(i)) / Float32(half)
                var tap = view.sample(
                    u + inv_x * Float32(i) * settings.anamorphic_scale, v
                ).unpremultiplied()
                var lum = luminance_of(tap.r, tap.g, tap.b)
                var keep = max(lum - settings.threshold, Float32(0)) * softness
                r += tap.r * keep
                g += tap.g * keep
                b += tap.b * keep
            streak.append(
                FloatColor(
                    r * ANAMORPHIC_TINT_R,
                    g * ANAMORPHIC_TINT_G,
                    b * ANAMORPHIC_TINT_B,
                    1,
                )
            )
    var shown = _read_back(streak, width, height, frame)
    for slot in range(len(frame.colors)):  # pragma: no branch
        var under = frame.colors[slot]
        var add = shown[slot]
        frame.colors[slot] = FloatColor(
            under.r + add.r, under.g + add.g, under.b + add.b, under.a
        )
        frame.data[slot] = False
    _ = before^


# --- LensflareNode -----------------------------------------------------------


def _fract(x: Float32) -> Float32:
    """Return GLSL's `fract`."""
    return x - floor(x)


def lensflare_light(mut frame: RenderTarget, settings: DisplaySettings):
    """Add three.js's `LensflareNode` to the frame: ghosts of the light
    above a threshold, mirrored through the center, at a smaller size.

    The flare target is the frame's size over `downSampleRatio`, rounded.
    Each ghost is read along the line from the mirrored pixel toward the
    center, wrapped into the frame, weighted by one less its distance from
    the center to the power of the attenuation, and tinted.

    Args:
        frame: The frame, changed in place.
        settings: The ghosts' tint, threshold, count, spacing and
            attenuation, and the down sample ratio.
    """
    var width = max(
        Int(floor(Float32(frame.width) / settings.down_sample_ratio + 0.5)), 1
    )
    var height = max(
        Int(floor(Float32(frame.height) / settings.down_sample_ratio + 0.5)), 1
    )
    var before = frame.colors.copy()
    var view = LightView(before, frame.width, frame.height)
    var flare = List[FloatColor](capacity=width * height)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var tu = 1 - u_of(x, width)
            var tv = 1 - v_of(y, height)
            var gu = (0.5 - tu) * settings.ghost_spacing
            var gv = (0.5 - tv) * settings.ghost_spacing
            var r = Float32(0)
            var g = Float32(0)
            var b = Float32(0)
            for i in range(settings.ghost_samples):
                var su = _fract(tu + gu * Float32(i))
                var sv = _fract(tv + gv * Float32(i))
                var du = su - 0.5
                var dv = sv - 0.5
                var d = sqrt(du * du + dv * dv)
                var weight = pow(1 - d, settings.ghost_attenuation)
                var tap = view.sample(su, sv).unpremultiplied()
                r += (
                    max(tap.r - settings.flare_threshold, 0)
                    * settings.ghost_tint_r
                    * weight
                )
                g += (
                    max(tap.g - settings.flare_threshold, 0)
                    * settings.ghost_tint_g
                    * weight
                )
                b += (
                    max(tap.b - settings.flare_threshold, 0)
                    * settings.ghost_tint_b
                    * weight
                )
            flare.append(FloatColor(r, g, b, 0))
    var shown = _read_back(flare, width, height, frame)
    for slot in range(len(frame.colors)):  # pragma: no branch
        var under = frame.colors[slot]
        var add = shown[slot]
        frame.colors[slot] = FloatColor(
            under.r + add.r, under.g + add.g, under.b + add.b, under.a
        )
        frame.data[slot] = False
    _ = before^


# --- Bayer -------------------------------------------------------------------


def _bayer_table() -> List[Int]:
    """Return three.js's `bayer16` texture's 16 by 16 bytes, row by row
    from the top, as its embedded image holds them."""
    return [
        0,
        128,
        32,
        160,
        8,
        136,
        40,
        168,
        2,
        130,
        34,
        162,
        10,
        138,
        42,
        170,
        192,
        64,
        224,
        96,
        200,
        72,
        232,
        104,
        194,
        66,
        226,
        98,
        202,
        74,
        234,
        106,
        48,
        176,
        16,
        144,
        56,
        184,
        24,
        152,
        50,
        178,
        18,
        146,
        58,
        186,
        26,
        154,
        240,
        112,
        208,
        80,
        248,
        120,
        216,
        88,
        242,
        114,
        210,
        82,
        250,
        122,
        218,
        90,
        12,
        140,
        44,
        172,
        4,
        132,
        36,
        164,
        14,
        142,
        46,
        174,
        6,
        134,
        38,
        166,
        204,
        76,
        236,
        108,
        196,
        68,
        228,
        100,
        206,
        78,
        238,
        110,
        198,
        70,
        230,
        102,
        60,
        188,
        28,
        156,
        52,
        180,
        20,
        148,
        62,
        190,
        30,
        158,
        54,
        182,
        22,
        150,
        252,
        124,
        220,
        92,
        244,
        116,
        212,
        84,
        254,
        126,
        222,
        94,
        246,
        118,
        214,
        86,
        3,
        131,
        35,
        163,
        11,
        139,
        43,
        171,
        1,
        129,
        33,
        161,
        9,
        137,
        41,
        169,
        195,
        67,
        227,
        99,
        203,
        75,
        235,
        107,
        193,
        65,
        225,
        97,
        201,
        73,
        233,
        105,
        51,
        179,
        19,
        147,
        59,
        187,
        27,
        155,
        49,
        177,
        17,
        145,
        57,
        185,
        25,
        153,
        243,
        115,
        211,
        83,
        251,
        123,
        219,
        91,
        241,
        113,
        209,
        81,
        249,
        121,
        217,
        89,
        15,
        143,
        47,
        175,
        7,
        135,
        39,
        167,
        13,
        141,
        45,
        173,
        5,
        133,
        37,
        165,
        207,
        79,
        239,
        111,
        199,
        71,
        231,
        103,
        205,
        77,
        237,
        109,
        197,
        69,
        229,
        101,
        63,
        191,
        31,
        159,
        55,
        183,
        23,
        151,
        61,
        189,
        29,
        157,
        53,
        181,
        21,
        149,
        255,
        127,
        223,
        95,
        247,
        119,
        215,
        87,
        253,
        125,
        221,
        93,
        245,
        117,
        213,
        85,
    ]


def bayer16(x: Int, y: Int) -> Float32:
    """Return three.js's `bayer16`: the 16 by 16 Bayer matrix at a pixel,
    zero to one, as `textureLoad( bayer16Texture, ivec2( uv ) % 16 )`
    reads its red.

    Args:
        x: The pixel's column. It wraps every sixteen.
        y: The pixel's row, as the texture counts them from its first
            row. It wraps every sixteen.

    Returns:
        The byte over 255.
    """
    var column = ((x % 16) + 16) % 16
    var row = ((y % 16) + 16) % 16
    return Float32(_bayer_table()[row * 16 + column]) / 255
