# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Seeded noise for coats: value noise, fractal noise and cell noise.

`ihash`, `vnoise3` and `fbm3` are procedural-animals' own, bit for bit.
`cells3` is added here. It is Worley's cellular noise, and it lays out
spots, rosettes and patches on the skin in reference space, so each
mark rides the skin as the animal moves.
"""

from math.norm import squared_length3
from math.smoothstep import hermite_fade
from math.utils import mix_trilinear
from extensions.sdf.vector import V3
from std.math import floor, sqrt


def ihash(x: Int, y: Int, z: Int) -> Float64:
    """Return a hash of three integers in `[0, 1)`.

    The arithmetic is JavaScript's `Math.imul` on 32-bit words.

    Args:
        x: The first integer.
        y: The second integer.
        z: The third integer.

    Returns:
        The hash.
    """
    var a = UInt32(x & 0xFFFFFFFF) * UInt32(0x8DA6B343)
    var b = UInt32(y & 0xFFFFFFFF) * UInt32(0xD8163841)
    var c = UInt32(z & 0xFFFFFFFF) * UInt32(0xCB1AB31F)
    var h = a ^ b ^ c
    h = (h ^ (h >> 13)) * UInt32(0x5BD1E995)
    h = h ^ (h >> 15)
    return Float64(h) / 4294967296.0


def vnoise3(p: V3) -> Float64:
    """Return smooth value noise in `[0, 1)`, one cell per unit.

    Args:
        p: The point.

    Returns:
        The noise.
    """
    var fx = floor(p.x)
    var fy = floor(p.y)
    var fz = floor(p.z)
    var xi = Int(fx)
    var yi = Int(fy)
    var zi = Int(fz)
    var xf = p.x - fx
    var yf = p.y - fy
    var zf = p.z - fz
    var u = hermite_fade(xf)
    var v = hermite_fade(yf)
    var w = hermite_fade(zf)
    var c000 = ihash(xi, yi, zi)
    var c100 = ihash(xi + 1, yi, zi)
    var c010 = ihash(xi, yi + 1, zi)
    var c110 = ihash(xi + 1, yi + 1, zi)
    var c001 = ihash(xi, yi, zi + 1)
    var c101 = ihash(xi + 1, yi, zi + 1)
    var c011 = ihash(xi, yi + 1, zi + 1)
    var c111 = ihash(xi + 1, yi + 1, zi + 1)
    return mix_trilinear[DType.float64, 1](
        c000, c100, c010, c110, c001, c101, c011, c111, u, v, w
    )


def fbm3(p: V3, octaves: Int = 4) -> Float64:
    """Return fractal value noise in `[0, 1)`.

    Args:
        p: The point.
        octaves: How many octaves, each twice as fine and half as strong.

    Returns:
        The noise.
    """
    var a = 0.5
    var f = 1.0
    var s = 0.0
    var n = 0.0
    for i in range(octaves):
        var k = Float64(i)
        s += a * vnoise3(
            V3(p.x * f + k * 17.3, p.y * f - k * 9.1, p.z * f + k * 3.7)
        )
        n += a
        a *= 0.5
        f *= 2.03
    return s / n if n > 0.0 else 0.5


def centered_fbm(
    point: V3, scale: Float64, octaves: Int, shift: Float64 = 0.0
) -> Float64:
    """Return fractal noise at one scale on each axis, centered on zero.

    Args:
        point: The sample.
        scale: Cells per unit on each axis.
        octaves: How many octaves `fbm3` adds.
        shift: An extra offset on x.

    Returns:
        The noise, about minus one half through one half.
    """
    return (
        fbm3(
            V3(point.x * scale + shift, point.y * scale, point.z * scale),
            octaves,
        )
        - 0.5
    )


def centered_value(point: V3, scale: Float64, shift: Float64) -> Float64:
    """Return value noise at one scale on each axis, centered on zero.

    Args:
        point: The sample.
        scale: Cells per unit on each axis.
        shift: An extra offset on x.

    Returns:
        The noise, about minus one half through one half.
    """
    return (
        vnoise3(V3(point.x * scale + shift, point.y * scale, point.z * scale))
        - 0.5
    )


@fieldwise_init
struct Cell(ImplicitlyCopyable):
    """The nearest feature of cell noise: its distance, its gap to the
    second nearest, and a number in `[0, 1)` that names it."""

    var nearest: Float64
    var second: Float64
    var id: Float64


def cells3(p: V3, seed: Int) -> Cell:
    """Return Worley cell noise: one jittered feature point per unit cell.

    Args:
        p: The point, in cells.
        seed: Which layout. Different seeds give different points.

    Returns:
        The distances to the nearest and second nearest features, in
        cells, and the nearest feature's id.
    """
    var xi = Int(floor(p.x))
    var yi = Int(floor(p.y))
    var zi = Int(floor(p.z))
    var best = 9.0
    var next = 9.0
    var id = 0.0
    for n in range(27):  # pragma: no branch
        var cx = xi + n % 3 - 1
        var cy = yi + (n // 3) % 3 - 1
        var cz = zi + n // 9 - 1
        var jx = ihash(cx, cy, cz + seed * 101)
        var jy = ihash(cx + 31, cy, cz + seed * 101)
        var jz = ihash(cx, cy + 57, cz + seed * 101)
        var dx = Float64(cx) + jx - p.x
        var dy = Float64(cy) + jy - p.y
        var dz = Float64(cz) + jz - p.z
        var d = sqrt(squared_length3[DType.float64](dx, dy, dz))
        var closer = d < best
        next = best if closer else min(next, d)
        id = ihash(cx + 7, cy + 11, cz + seed * 101 + 13) if closer else id
        best = d if closer else best
    return Cell(best, next, id)
