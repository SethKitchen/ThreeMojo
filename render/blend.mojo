# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""How a fragment mixes into the pixel behind it: three.js's blending
modes and WebGL's blend factors and equations.

Both rasterizers call `blend_pixel`, the host from `RenderTarget.blend` and
the device from the pixel kernel, so the two agree by construction.

A blending mode is one integer, the value of `materials.material.Blending`.
The four named modes are small numbers. A custom mode packs its six parts
above `CUSTOM_BASE`, four bits each: the color's source and destination
factors and equation, then the alpha's. That is what lets a custom mode
ride the one integer every corner and every device state lane already
carries.

The modes are three.js's with `premultipliedAlpha` off, its default:

| Mode | Color | Alpha |
|---|---|---|
| normal | `src * a + dst * (1 - a)` | `a + dst_a * (1 - a)` |
| additive | `src * a + dst` | `a + dst_a` |
| subtractive | `dst * (1 - src)` | `dst_a` |
| multiply | `dst * src` | `dst_a * a` |

With `premultipliedAlpha` on, the fragment's color is multiplied by its
alpha first, three.js's `premultiplied_alpha_fragment`, and the named modes
take the factors three.js sets for a premultiplied source:

| Mode | Color | Alpha |
|---|---|---|
| normal | `src * a + dst * (1 - a)` | `a + dst_a * (1 - a)` |
| additive | `src * a + dst` | `a + dst_a` |
| subtractive | `dst * (1 - src * a)` | `dst_a` |
| multiply | `src * a * dst + dst * (1 - a)` | `dst_a` |

A custom mode keeps its own factors and reads the premultiplied color.
The four constant factors read the material's `blendColor` and
`blendAlpha`, WebGL's `blendColor`.

The pixel is stored premultiplied, as `render.target` explains, and the
factors read it as WebGL reads its framebuffer. Over an opaque pixel, alpha
one, stored and straight are the same numbers, so every mode agrees with
three.js there. The result's alpha is kept between zero and one and its
color above zero; the color is light and has no ceiling.
"""

# The first custom mode. Below it are the named modes.
comptime CUSTOM_BASE = 1 << 24
# Four bits a field.
comptime FIELD_BITS = 4
comptime FIELD_MASK = 15

# The named modes, as `materials.material` numbers them.
comptime NORMAL_MODE = 1
comptime ADDITIVE_MODE = 2
comptime SUBTRACTIVE_MODE = 3
comptime MULTIPLY_MODE = 4

comptime Rgba = SIMD[DType.float32, 4]


@fieldwise_init
struct BlendFactor(Equatable, ImplicitlyCopyable, Writable):
    """What a color or an alpha is multiplied by before the equation, as a
    type rather than a bare int. three.js: `ZeroFactor` and the rest."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the eleven factors.

        Returns:
            Whether the value names a factor.
        """
        return self.value >= 0 and self.value <= 14


comptime ZERO_FACTOR = BlendFactor(0)
comptime ONE_FACTOR = BlendFactor(1)
comptime SRC_COLOR_FACTOR = BlendFactor(2)
comptime ONE_MINUS_SRC_COLOR_FACTOR = BlendFactor(3)
comptime SRC_ALPHA_FACTOR = BlendFactor(4)
comptime ONE_MINUS_SRC_ALPHA_FACTOR = BlendFactor(5)
comptime DST_ALPHA_FACTOR = BlendFactor(6)
comptime ONE_MINUS_DST_ALPHA_FACTOR = BlendFactor(7)
comptime DST_COLOR_FACTOR = BlendFactor(8)
comptime ONE_MINUS_DST_COLOR_FACTOR = BlendFactor(9)
comptime SRC_ALPHA_SATURATE_FACTOR = BlendFactor(10)
# The material's `blendColor` and `blendAlpha`, WebGL's constant color.
# three.js's `ConstantColorFactor` and the three after it.
comptime CONSTANT_COLOR_FACTOR = BlendFactor(11)
comptime ONE_MINUS_CONSTANT_COLOR_FACTOR = BlendFactor(12)
comptime CONSTANT_ALPHA_FACTOR = BlendFactor(13)
comptime ONE_MINUS_CONSTANT_ALPHA_FACTOR = BlendFactor(14)


@fieldwise_init
struct BlendEquation(Equatable, ImplicitlyCopyable, Writable):
    """How the two weighted terms join, as a type rather than a bare int.
    three.js: `AddEquation` and the rest."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the five equations.

        Returns:
            Whether the value names an equation.
        """
        return self.value >= 0 and self.value <= 4


comptime ADD_EQUATION = BlendEquation(0)
comptime SUBTRACT_EQUATION = BlendEquation(1)
comptime REVERSE_SUBTRACT_EQUATION = BlendEquation(2)
comptime MIN_EQUATION = BlendEquation(3)
comptime MAX_EQUATION = BlendEquation(4)


def pack_custom(
    src: BlendFactor,
    dst: BlendFactor,
    equation: BlendEquation,
    src_alpha: BlendFactor,
    dst_alpha: BlendFactor,
    equation_alpha: BlendEquation,
) -> Int:
    """Return the integer a custom mode is carried as.

    Args:
        src: The source color's factor.
        dst: The destination color's factor.
        equation: How the color terms join.
        src_alpha: The source alpha's factor.
        dst_alpha: The destination alpha's factor.
        equation_alpha: How the alpha terms join.

    Returns:
        `CUSTOM_BASE` plus the six fields, four bits each.
    """
    return (
        CUSTOM_BASE
        | src.value
        | (dst.value << 4)
        | (equation.value << 8)
        | (src_alpha.value << 12)
        | (dst_alpha.value << 16)
        | (equation_alpha.value << 20)
    )


def _field(mode: Int, index: Int) -> Int:
    """Return one four-bit field of a custom mode."""
    return (mode >> (index * FIELD_BITS)) & FIELD_MASK


def is_valid_custom(mode: Int) -> Bool:
    """Return True if an integer is a custom mode with every field valid.

    Args:
        mode: The integer.

    Returns:
        Whether it packs six valid fields and nothing else.
    """
    return (
        mode >= CUSTOM_BASE
        and mode < CUSTOM_BASE * 2
        and BlendFactor(_field(mode, 0)).is_valid()
        and BlendFactor(_field(mode, 1)).is_valid()
        and BlendEquation(_field(mode, 2)).is_valid()
        and BlendFactor(_field(mode, 3)).is_valid()
        and BlendFactor(_field(mode, 4)).is_valid()
        and BlendEquation(_field(mode, 5)).is_valid()
    )


@always_inline
def _factor(code: Int, src: Rgba, dst: Rgba, constant: Rgba) -> Rgba:
    """Return a factor for all four channels, color and alpha alike.

    The alpha channel of each factor is WebGL's alpha rule for it: the
    source-color factor weighs alpha by the source alpha, and the
    saturate factor weighs it by one.
    """
    var one = Rgba(1)
    if code == CONSTANT_COLOR_FACTOR.value:
        return constant
    if code == ONE_MINUS_CONSTANT_COLOR_FACTOR.value:
        return one - constant
    if code == CONSTANT_ALPHA_FACTOR.value:
        return Rgba(constant[3])
    if code == ONE_MINUS_CONSTANT_ALPHA_FACTOR.value:
        return Rgba(1 - constant[3])
    if code == ZERO_FACTOR.value:
        return Rgba(0)
    if code == ONE_FACTOR.value:
        return one
    if code == SRC_COLOR_FACTOR.value:
        return src
    if code == ONE_MINUS_SRC_COLOR_FACTOR.value:
        return one - src
    if code == SRC_ALPHA_FACTOR.value:
        return Rgba(src[3])
    if code == ONE_MINUS_SRC_ALPHA_FACTOR.value:
        return Rgba(1 - src[3])
    if code == DST_ALPHA_FACTOR.value:
        return Rgba(dst[3])
    if code == ONE_MINUS_DST_ALPHA_FACTOR.value:
        return Rgba(1 - dst[3])
    if code == DST_COLOR_FACTOR.value:
        return dst
    if code == ONE_MINUS_DST_COLOR_FACTOR.value:
        return one - dst
    var saturated = min(src[3], 1 - dst[3])
    return Rgba(saturated, saturated, saturated, 1)


@always_inline
def _join(
    equation: Int, src: Rgba, dst: Rgba, src_term: Rgba, dst_term: Rgba
) -> Rgba:
    """Return the two weighted terms joined by an equation.

    `MIN_EQUATION` and `MAX_EQUATION` ignore the factors, as WebGL's do.
    """
    if equation == ADD_EQUATION.value:
        return src_term + dst_term
    if equation == SUBTRACT_EQUATION.value:
        return src_term - dst_term
    if equation == REVERSE_SUBTRACT_EQUATION.value:
        return dst_term - src_term
    if equation == MIN_EQUATION.value:
        return min(src, dst)
    return max(src, dst)


@always_inline
def _custom(mode: Int, src: Rgba, dst: Rgba, constant: Rgba) -> Rgba:
    """Return a custom mode applied, color and alpha by their own fields."""
    var color = _join(
        _field(mode, 2),
        src,
        dst,
        src * _factor(_field(mode, 0), src, dst, constant),
        dst * _factor(_field(mode, 1), src, dst, constant),
    )
    var alpha = _join(
        _field(mode, 5),
        src,
        dst,
        src * _factor(_field(mode, 3), src, dst, constant),
        dst * _factor(_field(mode, 4), src, dst, constant),
    )
    return Rgba(color[0], color[1], color[2], alpha[3])


@always_inline
def blend_pixel(dst: Rgba, src: Rgba, mode: Int) -> Rgba:
    """Return a pixel after a fragment is mixed into it, with straight
    alpha and no constant color.

    `blend_fragment` with `premultipliedAlpha` off and a black, clear
    constant: three.js's material defaults.

    Args:
        dst: The pixel as stored, premultiplied.
        src: The fragment's color with straight alpha.
        mode: A named mode or a custom one.

    Returns:
        What `blend_fragment` returns.
    """
    return blend_fragment(dst, src, mode, False, Rgba(0))


@always_inline
def _named(mode: Int, premultiplied: Bool) -> Int:
    """Return the custom mode a named mode applies, for a straight or a
    premultiplied source. Normal is applied by `blend_fragment` itself."""
    if mode == ADDITIVE_MODE:
        if premultiplied:
            return pack_custom(
                ONE_FACTOR,
                ONE_FACTOR,
                ADD_EQUATION,
                ONE_FACTOR,
                ONE_FACTOR,
                ADD_EQUATION,
            )
        return pack_custom(
            SRC_ALPHA_FACTOR,
            ONE_FACTOR,
            ADD_EQUATION,
            ONE_FACTOR,
            ONE_FACTOR,
            ADD_EQUATION,
        )
    if mode == SUBTRACTIVE_MODE:
        return pack_custom(
            ZERO_FACTOR,
            ONE_MINUS_SRC_COLOR_FACTOR,
            ADD_EQUATION,
            ZERO_FACTOR,
            ONE_FACTOR,
            ADD_EQUATION,
        )
    if premultiplied:
        return pack_custom(
            DST_COLOR_FACTOR,
            ONE_MINUS_SRC_ALPHA_FACTOR,
            ADD_EQUATION,
            ZERO_FACTOR,
            ONE_FACTOR,
            ADD_EQUATION,
        )
    return pack_custom(
        ZERO_FACTOR,
        SRC_COLOR_FACTOR,
        ADD_EQUATION,
        ZERO_FACTOR,
        SRC_ALPHA_FACTOR,
        ADD_EQUATION,
    )


@always_inline
def blend_fragment(
    dst: Rgba, src: Rgba, mode: Int, premultiplied: Bool, constant: Rgba
) -> Rgba:
    """Return a pixel after a fragment is mixed into it.

    Args:
        dst: The pixel as stored, premultiplied.
        src: The fragment's color with straight alpha. The alpha is kept
            between zero and one first.
        mode: A named mode or a custom one.
        premultiplied: Whether the material's `premultipliedAlpha` is on:
            the color is multiplied by the alpha first, and a named mode
            takes three.js's premultiplied factors.
        constant: The constant color the four constant factors read,
            three.js's `blendColor` with `blendAlpha` as its alpha.

    Returns:
        The new pixel, premultiplied for the normal mode, as WebGL's
        blend leaves it for the others. Its alpha is between zero and one
        and its color is at least zero.
    """
    var share = max(Float32(0), min(Float32(1), src[3]))
    var fragment = Rgba(src[0], src[1], src[2], share)
    if premultiplied:
        fragment = Rgba(src[0] * share, src[1] * share, src[2] * share, share)
    var out: Rgba
    if mode == NORMAL_MODE:
        # The same sum either way: a straight source is weighed by its
        # alpha here, and a premultiplied one was weighed already.
        var keep = 1 - share
        out = Rgba(
            src[0] * share + dst[0] * keep,
            src[1] * share + dst[1] * keep,
            src[2] * share + dst[2] * keep,
            share + dst[3] * keep,
        )
    elif mode >= ADDITIVE_MODE and mode <= MULTIPLY_MODE:
        out = _custom(_named(mode, premultiplied), fragment, dst, constant)
    else:
        out = _custom(mode, fragment, dst, constant)
    return Rgba(
        max(Float32(0), out[0]),
        max(Float32(0), out[1]),
        max(Float32(0), out[2]),
        max(Float32(0), min(Float32(1), out[3])),
    )
