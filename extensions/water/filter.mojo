# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Screen-space mip level for one texture footprint.

Clearwater turns mipmaps on for the ocean, the caustics and the pebble
photograph, and sets an anisotropy of 8, 8 and 16. A sample without that
filter aliases. The level is the OpenGL choice: `log2` of the long texel
derivative divided by the anisotropy.
"""

from math.norm import squared_length2
from std.math import floor, log, sqrt


@fieldwise_init
struct FilterStep(ImplicitlyCopyable):
    """One anisotropic footprint: a mip level and a major-axis span."""

    var lod: Float32
    """Mip level, never below 0 and never above the chain."""
    var taps: Int
    """How many taps cover the major axis."""
    var du: Float32
    """Major-axis change in `u` across one pixel."""
    var dv: Float32
    """Major-axis change in `v` across one pixel."""


def anisotropic_step(
    du_dx: Float32,
    dv_dx: Float32,
    du_dy: Float32,
    dv_dy: Float32,
    width: Float32,
    height: Float32,
    max_aniso: Float32,
    lod_bias: Float32,
    max_lod: Float32,
) -> FilterStep:
    """Return the mip level and the major axis of one pixel footprint.

    Args:
        du_dx: Change in `u` for one pixel to the right.
        dv_dx: Change in `v` for one pixel to the right.
        du_dy: Change in `u` for one pixel up.
        dv_dy: Change in `v` for one pixel up.
        width: Texels across the base level.
        height: Texels down the base level.
        max_aniso: The most taps along the major axis.
        lod_bias: Added to the computed level. Caustics use 1.
        max_lod: The coarsest level in the chain.

    Returns:
        The clamped level, the tap count and the major-axis derivative.
    """
    var ax = du_dx * width
    var ay = dv_dx * height
    var bx = du_dy * width
    var by = dv_dy * height
    var len_x = sqrt(squared_length2[DType.float32](ax, ay))
    var len_y = sqrt(squared_length2[DType.float32](bx, by))
    var major = len_x
    var minor = len_y
    var du = du_dx
    var dv = dv_dx
    if len_y > len_x:
        major = len_y
        minor = len_x
        du = du_dy
        dv = dv_dy
    if minor < 1e-8:
        minor = 1e-8
    if major < minor:
        major = minor
    var ratio = major / minor
    if ratio > max_aniso:
        ratio = max_aniso
    var lod = log(major / ratio) * 1.4426950408889634 + lod_bias
    if lod < 0.0:
        lod = 0.0
    if lod > max_lod:
        lod = max_lod
    return FilterStep(lod, Int(ratio), du, dv)


def lod_blend(lod: Float32, levels: Int) -> Tuple[Int, Int, Float32]:
    """Return the two mip levels a sample blends, and the blend.

    Args:
        lod: The mip level.
        levels: The coarsest level in the chain.

    Returns:
        The finer level, the coarser level held at `levels`, and how far
        the sample is from the finer level toward the coarser one.
    """
    var finer = Int(floor(lod))
    var coarser = finer + 1
    if coarser > levels:
        coarser = levels
    return finer, coarser, lod - Float32(finer)


def major_axis_offset(index: Int, count: Int) -> Float32:
    """Return one tap's place on the major axis, from minus one half to one half.

    Args:
        index: The tap, from zero.
        count: How many taps. It is at least one.

    Returns:
        `(index + 0.5) / count - 0.5`.
    """
    return (Float32(index) + 0.5) / Float32(count) - 0.5
