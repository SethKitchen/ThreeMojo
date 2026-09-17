# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Tone mapping, from three.js's `tonemapping_pars_fragment` shader chunk.

A render target holds light, and light has no top: two lamps on a white
surface come to two, and `resolve` has so far shown that as white, clamping
once at the end. Tone mapping is the other answer to the same question. It
squeezes the whole range of light into what a display can show, so a scene
with bright and dark parts keeps both rather than losing the bright ones to
the clamp. three.js offers six curves, and they are ported here operator for
operator: linear, Reinhard, Cineon, ACES filmic, AgX and Khronos neutral,
each scaled first by `toneMappingExposure`.

**Applied once, to the finished image.** three.js tone maps every fragment
in its shader, before that fragment is blended, so a translucent surface
mixes an already-compressed color with the compressed color behind it. Here
the curve is applied in `RenderTarget.resolve`, to the composited linear
light of each pixel, just before it is encoded, which is where a
post-processing tone map sits and what a camera does: it sees the light
that reaches it, not each surface's separately. On an opaque pixel that
no fog reaches, the two orders give the same answer up to rounding. A
fogged pixel does not: the fog is mixed in linear light before the
curve here, and after the encode there. A translucent pixel does not
either, by design. And no bit-for-bit equality with another
implementation is promised: `exp2` of `log2` rounds differently from a
`pow`. Applied at the end, the curve also never sees the uv debug view,
which is coordinates rather than light.

**Shared with the kernel.** The GPU encodes its own pixels, so it tone maps
its own pixels, with this module's `tone_map`, from the same numbers. The
curves are written with `exp2` and `log2` where three.js has `pow`, so the
host and the device compute them from intrinsics both have, as `falloff`
is.
"""

from render.framebuffer import FloatColor
from std.math import exp2, isfinite, log2, max, min


@fieldwise_init
struct ToneMapping(Equatable, ImplicitlyCopyable, Writable):
    """Which curve compresses the light, as a type rather than an int.

    See `core.object3d.NodeId` for why. The type stops a bare integer at
    compile time; it does not stop `ToneMapping(9)`, which `Renderer`,
    `RenderTarget.resolve` and `GpuRenderer.draw` each refuse.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the seven named curves."""
        return (
            self == NO_TONE_MAPPING
            or self == LINEAR_TONE_MAPPING
            or self == REINHARD_TONE_MAPPING
            or self == CINEON_TONE_MAPPING
            or self == ACES_FILMIC_TONE_MAPPING
            or self == AGX_TONE_MAPPING
            or self == NEUTRAL_TONE_MAPPING
        )


# Light is clamped at the end and nothing else. three.js's `NoToneMapping`,
# and the default here as there. The exposure is not applied.
comptime NO_TONE_MAPPING = ToneMapping(0)
# Scaled by the exposure and clamped. three.js's `LinearToneMapping`.
comptime LINEAR_TONE_MAPPING = ToneMapping(1)
# `c / (1 + c)`: nothing ever reaches white. three.js's `ReinhardToneMapping`.
comptime REINHARD_TONE_MAPPING = ToneMapping(2)
# Hejl and Burgess-Dawson's filmic curve. three.js's `CineonToneMapping`.
comptime CINEON_TONE_MAPPING = ToneMapping(3)
# Stephen Hill's fit of the ACES reference rendering transform, brightened
# as three.js brightens it. three.js's `ACESFilmicToneMapping`.
comptime ACES_FILMIC_TONE_MAPPING = ToneMapping(4)
# Blender's AgX, through rec. 2020, as Filament and three.js carry it.
# three.js's `AgXToneMapping`.
comptime AGX_TONE_MAPPING = ToneMapping(5)
# The Khronos PBR neutral curve: hue-preserving up to a knee, then a soft
# roll toward white. three.js's `NeutralToneMapping`.
comptime NEUTRAL_TONE_MAPPING = ToneMapping(6)


def check_tone_mapping(mode: ToneMapping, exposure: Float32) raises:
    """Refuse a curve that is none of the seven, or an exposure that is
    negative or not finite.

    The one list, asked by every boundary that takes the pair --
    `Renderer.set_tone_mapping`, `RenderTarget.resolve` and `shown`, and
    `GpuRenderer.draw` -- so that they cannot drift apart. The type stops
    a bare integer; it does not stop `ToneMapping(9)`, and `tone_map`
    cannot raise on what it is handed, so the boundary does. An infinite
    exposure is refused as well as a negative one: infinity over one plus
    infinity is not a number, and nothing downstream could say so.

    Args:
        mode: The curve.
        exposure: What the light is scaled by first.

    Raises:
        Error: If the curve is not a named one, or the exposure is
            negative or not finite.
    """
    if not mode.is_valid():
        raise Error("A tone mapping that is none of the seven")
    if not isfinite(exposure) or exposure < 0:
        raise Error("A tone mapping exposure must be finite and not negative")


def _saturate(value: Float32) -> Float32:
    """Return `value` clamped to zero to one, GLSL's `saturate`."""
    return max(Float32(0), min(Float32(1), value))


def _pow(base: Float32, exponent: Float32) -> Float32:
    """Return `base` to `exponent` for a base of zero or more.

    Written as `exp2(exponent * log2(base))` so the kernel and the host
    compute it the same way from two intrinsics both already have, as
    `falloff` is. A base of zero is zero, which is what every curve here
    wants of it and what `log2` would not give.
    """
    if base <= 0:
        return 0
    return exp2(exponent * log2(base))


def _linear(
    r: Float32, g: Float32, b: Float32, exposure: Float32
) -> FloatColor:
    """three.js's `LinearToneMapping`: the exposure, then the clamp."""
    return FloatColor(
        _saturate(exposure * r),
        _saturate(exposure * g),
        _saturate(exposure * b),
    )


def _reinhard(
    r: Float32, g: Float32, b: Float32, exposure: Float32
) -> FloatColor:
    """three.js's `ReinhardToneMapping`: `c / (1 + c)` after the exposure."""
    var er = r * exposure
    var eg = g * exposure
    var eb = b * exposure
    return FloatColor(
        _saturate(er / (1 + er)),
        _saturate(eg / (1 + eg)),
        _saturate(eb / (1 + eb)),
    )


def _cineon_channel(value: Float32) -> Float32:
    """One channel of the Hejl and Burgess-Dawson curve, exposure applied."""
    var c = max(Float32(0), value - 0.004)
    return _pow(
        (c * (6.2 * c + 0.5)) / (c * (6.2 * c + 1.7) + 0.06), Float32(2.2)
    )


def _cineon(
    r: Float32, g: Float32, b: Float32, exposure: Float32
) -> FloatColor:
    """three.js's `CineonToneMapping`."""
    return FloatColor(
        _cineon_channel(r * exposure),
        _cineon_channel(g * exposure),
        _cineon_channel(b * exposure),
    )


def _rrt_and_odt_fit(v: Float32) -> Float32:
    """One channel of three.js's `RRTAndODTFit`, the ACES curve itself."""
    var a = v * (v + 0.0245786) - 0.000090537
    var b = v * (0.983729 * v + 0.4329510) + 0.238081
    return a / b


def _aces(r: Float32, g: Float32, b: Float32, exposure: Float32) -> FloatColor:
    """three.js's `ACESFilmicToneMapping`.

    Scaled by the exposure over 0.6, three.js's brightening for a lit
    viewing environment; into the ACES working primaries by
    `ACESInputMat`; through the fit; back out by `ACESOutputMat`; clamped.
    Each matrix is applied as its three rows, written out, since the kernel
    has no matrix type.
    """
    var scale = exposure / 0.6
    var sr = r * scale
    var sg = g * scale
    var sb = b * scale
    var ir = 0.59719 * sr + 0.35458 * sg + 0.04823 * sb
    var ig = 0.07600 * sr + 0.90834 * sg + 0.01566 * sb
    var ib = 0.02840 * sr + 0.13383 * sg + 0.83777 * sb
    var fr = _rrt_and_odt_fit(ir)
    var fg = _rrt_and_odt_fit(ig)
    var fb = _rrt_and_odt_fit(ib)
    return FloatColor(
        _saturate(1.60475 * fr - 0.53108 * fg - 0.07367 * fb),
        _saturate(-0.10208 * fr + 1.10813 * fg - 0.00605 * fb),
        _saturate(-0.00327 * fr - 0.07276 * fg + 1.07602 * fb),
    )


# three.js's AgX constants: the log2 range the encoding maps to zero to
# one, `log2(2^-10 * 0.18)` to `log2(2^6.5 * 0.18)`.
comptime AGX_MIN_EV = Float32(-12.47393)
comptime AGX_MAX_EV = Float32(4.026069)


def _agx_contrast(x: Float32) -> Float32:
    """One channel of three.js's `agxDefaultContrastApprox`, the sigmoid."""
    var x2 = x * x
    var x4 = x2 * x2
    return (
        15.5 * x4 * x2
        - 40.14 * x4 * x
        + 31.96 * x4
        - 6.868 * x2 * x
        + 0.4298 * x2
        + 0.1191 * x
        - 0.00232
    )


def _agx_encode(value: Float32) -> Float32:
    """One channel's log2 encoding into zero to one, then the sigmoid."""
    var floored = max(value, Float32(1e-10))
    var ev = (log2(floored) - AGX_MIN_EV) / (AGX_MAX_EV - AGX_MIN_EV)
    return _agx_contrast(_saturate(ev))


def _agx(r: Float32, g: Float32, b: Float32, exposure: Float32) -> FloatColor:
    """three.js's `AgXToneMapping`.

    Into rec. 2020, through the inset matrix, log2-encoded and put through
    the sigmoid, through the outset matrix, linearized with a 2.2 power,
    back to linear sRGB, and clamped. Every matrix as its rows, as in
    `_aces`.
    """
    var er = r * exposure
    var eg = g * exposure
    var eb = b * exposure
    # LINEAR_SRGB_TO_LINEAR_REC2020.
    var wr = 0.6274 * er + 0.3293 * eg + 0.0433 * eb
    var wg = 0.0691 * er + 0.9195 * eg + 0.0113 * eb
    var wb = 0.0164 * er + 0.0880 * eg + 0.8956 * eb
    # AgXInsetMatrix.
    var ir = (
        0.856627153315983 * wr
        + 0.0951212405381588 * wg
        + 0.0482516061458583 * wb
    )
    var ig = (
        0.137318972929847 * wr + 0.761241990602591 * wg + 0.101439036467562 * wb
    )
    var ib = (
        0.11189821299995 * wr + 0.0767994186031903 * wg + 0.811302368396859 * wb
    )
    var cr = _agx_encode(ir)
    var cg = _agx_encode(ig)
    var cb = _agx_encode(ib)
    # AgXOutsetMatrix.
    var xr = (
        1.1271005818144368 * cr
        - 0.11060664309660323 * cg
        - 0.016493938717834573 * cb
    )
    var xg = (
        -0.1413297634984383 * cr
        + 1.157823702216272 * cg
        - 0.016493938717834257 * cb
    )
    var xb = (
        -0.14132976349843826 * cr
        - 0.11060664309660294 * cg
        + 1.2519364065950405 * cb
    )
    var lr = _pow(max(Float32(0), xr), Float32(2.2))
    var lg = _pow(max(Float32(0), xg), Float32(2.2))
    var lb = _pow(max(Float32(0), xb), Float32(2.2))
    # LINEAR_REC2020_TO_LINEAR_SRGB.
    return FloatColor(
        _saturate(1.6605 * lr - 0.5876 * lg - 0.0728 * lb),
        _saturate(-0.1246 * lr + 1.1329 * lg - 0.0083 * lb),
        _saturate(-0.0182 * lr - 0.1006 * lg + 1.1187 * lb),
    )


# three.js's Khronos neutral constants: where the compression starts, and
# how much the roll toward white desaturates.
comptime NEUTRAL_START = Float32(0.8 - 0.04)
comptime NEUTRAL_DESATURATION = Float32(0.15)


def _neutral(
    r: Float32, g: Float32, b: Float32, exposure: Float32
) -> FloatColor:
    """three.js's `NeutralToneMapping`.

    An offset lifts the darkest channel off black, then a color whose
    brightest channel is past the knee is scaled down onto a curve that
    approaches one and mixed a little toward gray as it goes.
    """
    var er = r * exposure
    var eg = g * exposure
    var eb = b * exposure
    var darkest = min(er, min(eg, eb))
    var offset = Float32(0.04)
    if darkest < 0.08:
        offset = darkest - 6.25 * darkest * darkest
    er -= offset
    eg -= offset
    eb -= offset
    var peak = max(er, max(eg, eb))
    if peak < NEUTRAL_START:
        return FloatColor(er, eg, eb)
    var d = 1 - NEUTRAL_START
    var new_peak = 1 - d * d / (peak + d - NEUTRAL_START)
    var scale = new_peak / peak
    er *= scale
    eg *= scale
    eb *= scale
    var gray = 1 - 1 / (NEUTRAL_DESATURATION * (peak - new_peak) + 1)
    return FloatColor(
        er + (new_peak - er) * gray,
        eg + (new_peak - eg) * gray,
        eb + (new_peak - eb) * gray,
    )


def tone_map(
    color: FloatColor, mode: ToneMapping, exposure: Float32
) -> FloatColor:
    """Return `color` compressed by `mode` for a display, alpha kept.

    Each curve by name, as the kernel asks for each shading mode by name,
    so there is no "else" for an unrecognized curve to fall into
    differently on each side: `NO_TONE_MAPPING`, and any value that is not
    a named curve, leave the color alone. The callers that can raise refuse
    an unknown curve before this is asked.

    Args:
        color: Linear light, straight alpha, with no top.
        mode: Which curve.
        exposure: What the light is scaled by first, three.js's
            `toneMappingExposure`. One leaves it as it is. Not applied by
            `NO_TONE_MAPPING`, as three.js does not apply it.

    Returns:
        The compressed color, every channel within zero to one for the six
        curves, with `color`'s alpha.
    """
    var mapped = color
    if mode == LINEAR_TONE_MAPPING:
        mapped = _linear(color.r, color.g, color.b, exposure)
    elif mode == REINHARD_TONE_MAPPING:
        mapped = _reinhard(color.r, color.g, color.b, exposure)
    elif mode == CINEON_TONE_MAPPING:
        mapped = _cineon(color.r, color.g, color.b, exposure)
    elif mode == ACES_FILMIC_TONE_MAPPING:
        mapped = _aces(color.r, color.g, color.b, exposure)
    elif mode == AGX_TONE_MAPPING:
        mapped = _agx(color.r, color.g, color.b, exposure)
    elif mode == NEUTRAL_TONE_MAPPING:
        mapped = _neutral(color.r, color.g, color.b, exposure)
    return FloatColor(mapped.r, mapped.g, mapped.b, color.a)
