# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A lattice hash and smooth value noise for placement and wind.

The hash gives each pair of integers and a seed one number from zero to
one. The same arguments give the same number on every machine, so a field
grows the same blades in every run, and a cluster can grow its blades
again on any frame without storing them.

The value noise blends the hashes of the four lattice corners round a
point with a smoothstep. It is cheaper than simplex noise, and the
patches of a meadow and the gusts of the wind need no more.
"""

from std.math import floor


def hash01(a: Int, b: Int, seed: Int) -> Float32:
    """Return a number from zero to one for two integers and a seed.

    Args:
        a: The first lattice coordinate, or an index.
        b: The second lattice coordinate, or a second index.
        seed: Which of the many fields to read.

    Returns:
        The hash, from zero to one.
    """
    var mixed = a * 374761393 + b * 668265263 + seed * 1442695041
    var h = UInt32(mixed & 0xFFFFFFFF)
    h = (h ^ (h >> 15)) * UInt32(0x2C1B3C6D)
    h = (h ^ (h >> 12)) * UInt32(0x297A2D39)
    h = h ^ (h >> 15)
    return Float32(h) / Float32(4294967295.0)


def _smooth(t: Float32) -> Float32:
    """Return the smoothstep of a fraction from zero to one."""
    return t * t * (3 - 2 * t)


def value_noise(x: Float32, z: Float32, seed: Int) -> Float32:
    """Return smooth value noise at a point, from zero to one.

    The lattice has one corner a unit. Scale the point to set the size of
    the patches.

    Args:
        x: The first coordinate, in lattice units.
        z: The second coordinate, in lattice units.
        seed: Which field to read.

    Returns:
        The noise, from zero to one.
    """
    var fx = floor(x)
    var fz = floor(z)
    var ix = Int(fx)
    var iz = Int(fz)
    var sx = _smooth(x - fx)
    var sz = _smooth(z - fz)
    var a = hash01(ix, iz, seed)
    var b = hash01(ix + 1, iz, seed)
    var c = hash01(ix, iz + 1, seed)
    var d = hash01(ix + 1, iz + 1, seed)
    var near = a + (b - a) * sx
    var far = c + (d - c) * sx
    return near + (far - near) * sz


def layered_noise(x: Float32, z: Float32, seed: Int) -> Float32:
    """Return two octaves of value noise, from zero to one.

    The second octave is 2.3 times finer and weighs 0.3, so a patch has a
    ragged edge rather than a round one.

    Args:
        x: The first coordinate, in lattice units.
        z: The second coordinate, in lattice units.
        seed: Which field to read.

    Returns:
        The noise, from zero to one.
    """
    var coarse = value_noise(x, z, seed)
    var fine = value_noise(x * 2.3 + 5.1, z * 2.3 + 1.7, seed + 1)
    return coarse * 0.7 + fine * 0.3
