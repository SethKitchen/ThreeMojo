# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The sRGB transfer function, and which space a colour is in.

**Light adds; sRGB does not.** A pixel value of 128 is not half the light of
255 — it is about 21.6% of it. sRGB spends more of its 256 steps on dark
values, where the eye can tell them apart, which is why eight bits look
acceptable at all. Every image you will ever load, and every colour picked in
a paint program, is encoded that way.

Arithmetic on light has to happen in the other space, where the numbers are
proportional to how much light there is:

    filtering    blending two neighbouring texels
    shading      multiplying a colour by a Lambert term
    blending     mixing a translucent surface with what is behind it

Doing any of those on encoded values is wrong in a specific, visible way:
midtones come out too dark. Blend black and white in sRGB bytes and you get
128, which is 21.6% of the light — the answer that looks like half the light
is 188.

So this project decodes on the way in and encodes on the way out, and
everything between is linear. three.js draws the same distinction, and names
the same three cases: colour images are `SRGB`, data that merely happens to be
stored in an image — a normal map, a height field — is `LINEAR` and must not
be decoded, and alpha is never colour and is never decoded either.

The piecewise curve is the real one rather than a 2.2 power approximation. It
is four lines, the linear segment near black matters at exactly the values
eight bits are trying hardest to preserve, and being approximately right about
a definition is a poor trade for nothing.
"""

from std.math import pow


@fieldwise_init
struct ColorSpace(Equatable, ImplicitlyCopyable, Writable):
    """What a stored sample means, as a type rather than a bare int.

    See `core.object3d.NodeId` for why these are wrapped. `value` is what
    crosses to the GPU, where a descriptor table holds plain integers.
    """

    var value: Int


# A colour image: stored encoded, decoded when read.
comptime SRGB = ColorSpace(0)
# Data that is not colour, or colour already linear: used as stored.
comptime LINEAR = ColorSpace(1)
# A file said something about its colour that could not be interpreted -- an
# ICC profile, say. Not a third transfer function: a refusal to guess, which
# the caller has to settle before the samples can be used as colour.
comptime UNKNOWN_SPACE = ColorSpace(2)


def srgb_to_linear(value: Float32) -> Float32:
    """Return an sRGB-encoded value as the amount of light it stands for.

    Args:
        value: An encoded channel, nominally 0 to 1.

    Returns:
        The linear value. 0 and 1 map to themselves; 0.5 maps to about 0.214.
    """
    if value <= 0.04045:
        return value / 12.92
    return pow((value + 0.055) / 1.055, Float32(2.4))


def linear_to_srgb(value: Float32) -> Float32:
    """Return an amount of light as the sRGB value that displays it.

    The inverse of `srgb_to_linear`, applied once at the very end — a
    framebuffer holds what a display should show, not what the light was.

    Args:
        value: A linear channel, nominally 0 to 1.

    Returns:
        The encoded value.
    """
    if value <= 0.0031308:
        return value * 12.92
    return 1.055 * pow(value, Float32(1) / Float32(2.4)) - 0.055


def decode_ramp() -> List[Float32]:
    """Return the 256 linear values an sRGB byte can stand for.

    Sampling a texture happens per fragment, and `pow` per fragment per
    channel is a great deal of work for a function with 256 possible inputs.
    The table is built once per texture and indexed by the byte.

    Returns:
        Entry `n` is `srgb_to_linear(n / 255)`.
    """
    var ramp = List[Float32]()
    for step in range(256):  # pragma: no branch
        ramp.append(srgb_to_linear(Float32(step) / 255))
    return ramp^
