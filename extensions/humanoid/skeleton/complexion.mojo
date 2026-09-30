# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Pigment and texture of the skin, the hair and the iris from a genome.

The skin's tone runs along a ramp of six swatches, from very fair to
very dark, set by `MELANIN`. `UNDERTONE` then moves it toward pink or
toward olive. The skin's maps add what a single color cannot: blotches
of redness where the blood shows, pores, fine furrows, and the freckles
and moles `FRECKLES` asks for. Every map tiles in both directions, so
the seam where a body's cylindrical texture coordinates meet is not
seen.

    var tone = skin_tone(genome)
    var albedo = skin_albedo(128, genome)
    var relief = skin_relief(128)

The swatches are authored. They are close to published photographs of
the Fitzpatrick types, but they are not a measured reflectance table.
"""

from extensions.humanoid.genome import (
    FRECKLES,
    Genome,
    HAIR_MELANIN,
    HAIR_REDNESS,
    IRIS_MELANIN,
    MELANIN,
    UNDERTONE,
    check_genome,
)
from render.framebuffer import Color
from render.srgb import LINEAR, SRGB
from render.texture import IGNORED, REPEAT, Texture
from std.math import cos, floor, max, min, sin, sqrt

comptime MIN_MAP = 8
comptime MAX_MAP = 512


def _lerp(a: Float32, b: Float32, t: Float32) -> Float32:
    """Return `a` moved toward `b` by `t`."""
    return a + (b - a) * t


def _clamp(value: Float32, low: Float32, high: Float32) -> Float32:
    """Return `value` held to `low` through `high`."""
    return max(low, min(high, value))


def _smooth(edge0: Float32, edge1: Float32, x: Float32) -> Float32:
    """Return the Hermite step from `edge0` to `edge1`."""
    var t = _clamp((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def _byte(value: Float32) -> UInt8:
    """Return `value` rounded and held to one byte."""
    return UInt8(Int(_clamp(value, 0, 255) + Float32(0.5)))


@fieldwise_init
struct Tone(ImplicitlyCopyable):
    """A color in sRGB byte units, held as floats while it is mixed."""

    var r: Float32
    var g: Float32
    var b: Float32

    def mix(self, other: Tone, t: Float32) -> Tone:
        """Return this tone moved toward `other` by `t`.

        Args:
            other: The tone to move toward.
            t: How far, 0 through 1.

        Returns:
            The mixed tone.
        """
        return Tone(
            _lerp(self.r, other.r, t),
            _lerp(self.g, other.g, t),
            _lerp(self.b, other.b, t),
        )

    def color(self) -> Color:
        """Return this tone as an opaque byte color.

        Returns:
            The color, each channel rounded and held to 0 through 255.
        """
        return Color(_byte(self.r), _byte(self.g), _byte(self.b))


def _ramp(stops: List[Tone], t: Float32) -> Tone:
    """Return the tone at `t`, 0 through 1, along evenly spaced stops."""
    var span = Float32(len(stops) - 1)
    var at = _clamp(t, 0, 1) * span
    var index = min(Int(at), len(stops) - 2)
    return stops[index].mix(stops[index + 1], at - Float32(index))


def _skin_tone(melanin: Float32, undertone: Float32) -> Tone:
    """Return the skin's mean color for two expressions."""
    # Fitzpatrick I, II, III, IV, V and VI, in that order.
    var stops: List[Tone] = [
        Tone(247, 219, 201),
        Tone(234, 192, 164),
        Tone(216, 167, 134),
        Tone(186, 132, 96),
        Tone(134, 88, 60),
        Tone(84, 55, 40),
    ]
    var tone = _ramp(stops, (melanin + 1) / 2)
    # A cool undertone shows more blood; a warm one more carotene and a
    # little olive.
    return Tone(
        tone.r * (1 - Float32(0.025) * undertone),
        tone.g * (1 + Float32(0.03) * undertone),
        tone.b * (1 - Float32(0.07) * undertone),
    )


def skin_tone(genome: Genome) raises -> Color:
    """Return the mean color of the skin that `genome` asks for.

    Args:
        genome: Reads `MELANIN` and `UNDERTONE`.

    Returns:
        An sRGB color: near (247, 219, 201) for the fairest skin and
        near (84, 55, 40) for the darkest.

    Raises:
        Error: If `genome` is not valid.
    """
    check_genome(genome, "skin")
    return _skin_tone(genome.get(MELANIN), genome.get(UNDERTONE)).color()


def skin_glow(genome: Genome) raises -> Color:
    """Return the color light takes on as it scatters out of the skin.

    Red light travels farthest in skin, so the glow at a grazing edge is
    a deep red that darkens as melanin rises.

    Args:
        genome: Reads `MELANIN`.

    Returns:
        An sRGB color for a sheen.

    Raises:
        Error: If `genome` is not valid.
    """
    check_genome(genome, "skin")
    var dark = (genome.get(MELANIN) + 1) / 2
    return Tone(236, 120, 96).mix(Tone(120, 58, 40), dark).color()


def hair_tone(genome: Genome) raises -> Color:
    """Return the mean color of the hair that `genome` asks for.

    Args:
        genome: Reads `HAIR_MELANIN` and `HAIR_REDNESS`.

    Returns:
        An sRGB color from pale blond through brown to black, pulled
        toward auburn and copper by redness.

    Raises:
        Error: If `genome` is not valid.
    """
    check_genome(genome, "hair")
    # Platinum, golden blond, light brown, dark brown and black.
    var stops: List[Tone] = [
        Tone(226, 206, 160),
        Tone(178, 138, 84),
        Tone(118, 80, 50),
        Tone(62, 40, 28),
        Tone(24, 18, 16),
    ]
    var tone = _ramp(stops, (genome.get(HAIR_MELANIN) + 1) / 2)
    var red = max(Float32(0), genome.get(HAIR_REDNESS))
    var copper = Tone(170, 72, 32).mix(tone, Float32(0.35))
    return tone.mix(copper, red * Float32(0.8)).color()


def iris_tone(genome: Genome) raises -> Color:
    """Return the mean color of the iris that `genome` asks for.

    Args:
        genome: Reads `IRIS_MELANIN`.

    Returns:
        An sRGB color from pale blue through gray-green and hazel to
        dark brown.

    Raises:
        Error: If `genome` is not valid.
    """
    check_genome(genome, "eye")
    var stops: List[Tone] = [
        Tone(104, 150, 196),
        Tone(106, 132, 128),
        Tone(122, 118, 70),
        Tone(112, 72, 36),
        Tone(52, 30, 18),
    ]
    return _ramp(stops, (genome.get(IRIS_MELANIN) + 1) / 2).color()


def _hash(x: Int, y: Int, seed: Int) -> Float32:
    """Return a value in 0 through 1 hashed from a lattice point."""
    var h = (
        UInt32(x) * 374761393
        + UInt32(y) * 668265263
        + UInt32(seed) * (2246822519)
    )
    h = (h ^ (h >> 13)) * 1274126177
    h = h ^ (h >> 16)
    return Float32(h & 0xFFFFFF) / Float32(0x1000000)


def _wrap(value: Int, period: Int) -> Int:
    """Return `value` modulo `period`, never negative.

    Mojo's `%` takes the sign of the divisor, as Python's does.
    """
    return value % period


def value_noise(
    x: Float32, y: Float32, period: Int, seed: Int, period_y: Int = 0
) -> Float32:
    """Return smooth lattice noise that repeats every `period` cells.

    Args:
        x: Across, in cells.
        y: Up, in cells.
        period: Cells before the pattern repeats across, and up too
            unless `period_y` is given.
        seed: Picks the pattern.
        period_y: Cells before the pattern repeats up, or zero for
            `period`.

    Returns:
        A value in 0 through 1.
    """
    var up = period_y
    if up <= 0:
        up = period
    var fx = floor(x)
    var fy = floor(y)
    var ix = Int(fx)
    var iy = Int(fy)
    var tx = x - fx
    var ty = y - fy
    tx = tx * tx * (3 - 2 * tx)
    ty = ty * ty * (3 - 2 * ty)
    var x0 = _wrap(ix, period)
    var x1 = _wrap(ix + 1, period)
    var y0 = _wrap(iy, up)
    var y1 = _wrap(iy + 1, up)
    var a = _lerp(_hash(x0, y0, seed), _hash(x1, y0, seed), tx)
    var b = _lerp(_hash(x0, y1, seed), _hash(x1, y1, seed), tx)
    return _lerp(a, b, ty)


def _fbm(
    x: Float32,
    y: Float32,
    size: Int,
    base: Int,
    octaves: Int,
    seed: Int,
    base_y: Int = 0,
) -> Float32:
    """Return tiling fractal noise centered on zero, about -0.5 to 0.5.

    `x` and `y` are in texels of a `size` map. The first octave has
    `base` cells across the map, and `base_y` up it, or `base` when that
    is zero; each next octave has twice as many.
    """
    var total = Float32(0)
    var weight = Float32(0.5)
    var norm = Float32(0)
    var cells = base
    var rows = base_y
    if rows <= 0:
        rows = base
    for octave in range(octaves):  # pragma: no branch
        var sx = Float32(cells) / Float32(size)
        var sy = Float32(rows) / Float32(size)
        total += weight * (
            value_noise(x * sx, y * sy, cells, seed + octave * 31, rows) - 0.5
        )
        norm += weight
        weight *= 0.5
        cells *= 2
        rows *= 2
    return total / norm


def _spots(
    x: Float32, y: Float32, size: Int, cell: Int, chance: Float32, seed: Int
) -> Float32:
    """Return how deep in a spot the texel is, 0 through 1.

    The map is cut into square cells `cell` texels across. Each cell
    holds a spot with probability `chance`, at a hashed place and of a
    hashed size, so the spots look scattered and not on a grid. The
    pattern repeats with the map.
    """
    var cells = max(1, size // cell)
    var width = Float32(size) / Float32(cells)
    var cx = Int(floor(x / width))
    var cy = Int(floor(y / width))
    var best = Float32(0)
    for dy in range(-1, 2):  # pragma: no branch
        for dx in range(-1, 2):  # pragma: no branch
            var gx = _wrap(cx + dx, cells)
            var gy = _wrap(cy + dy, cells)
            if _hash(gx, gy, seed) >= chance:
                continue
            var px = (Float32(cx + dx) + _hash(gx, gy, seed + 1)) * width
            var py = (Float32(cy + dy) + _hash(gx, gy, seed + 2)) * width
            var radius = width * (
                Float32(0.14) + Float32(0.22) * _hash(gx, gy, seed + 3)
            )
            var ex = x - px
            var ey = y - py
            var d = sqrt(ex * ex + ey * ey) / radius
            best = max(best, 1 - _smooth(0.55, 1.0, d))
    return best


def check_map_size(size: Int, name: String) raises:
    """Refuse a map size the skin's maps cannot use.

    Args:
        size: Width and height in texels.
        name: Name used in the error text.

    Raises:
        Error: If `size` is less than eight or more than 512.
    """
    if size < MIN_MAP:
        raise Error("A " + name + " map needs a size of at least eight")
    if size > MAX_MAP:
        raise Error("A " + name + " map's size cannot exceed 512")


def skin_albedo_pixels(size: Int, genome: Genome) raises -> List[UInt8]:
    """Return the RGBA bytes of a tiling skin color map.

    The mean is `skin_tone(genome)`. Broad blotches of redness and of
    pigment move it by a few percent, as they do on a face. Pores are
    small darker dots. Freckles are small brown spots, more of them as
    `FRECKLES` rises and fewer as `MELANIN` rises. A rare mole is a
    darker, rounder spot.

    Args:
        size: Width and height in texels, eight through 512.
        genome: Reads the skin's genes.

    Returns:
        `size * size * 4` bytes, row by row from the top.

    Raises:
        Error: If `size` is out of range or `genome` is not valid.
    """
    check_map_size(size, "skin")
    check_genome(genome, "skin")
    var melanin = genome.get(MELANIN)
    var tone = _skin_tone(melanin, genome.get(UNDERTONE))
    # Freckles only where the gene asks for them, and fewer on darker
    # skin, which is already dark.
    var freckle = max(Float32(0), genome.get(FRECKLES))
    var fair = 1 - _clamp(melanin + Float32(0.2), 0, 1)
    var freckle_chance = (
        freckle * Float32(0.6) * (Float32(0.3) + Float32(0.7) * fair)
    )
    var pore_cell = max(3, size // 64)
    var freckle_cell = max(4, size // 56)
    var mole_cell = max(8, size // 6)
    var pixels = List[UInt8](capacity=size * size * 4)
    for y in range(size):  # pragma: no branch
        var fy = Float32(y) + Float32(0.5)
        for x in range(size):  # pragma: no branch
            var fx = Float32(x) + Float32(0.5)
            # Broad variation in blood and in pigment.
            var blood = _fbm(fx, fy, size, 3, 3, 11)
            var pigment = _fbm(fx, fy, size, 4, 4, 23)
            var fine = _fbm(fx, fy, size, 32, 2, 37)
            var shade = 1 + Float32(0.08) * pigment + Float32(0.03) * fine
            var r = tone.r * shade * (1 + Float32(0.07) * blood)
            var g = tone.g * shade * (1 - Float32(0.03) * blood)
            var b = tone.b * shade * (1 - Float32(0.015) * blood)
            # Pores: a slight darkening at each opening.
            var pore = _spots(fx, fy, size, pore_cell, 0.7, 41)
            var dim = 1 - Float32(0.05) * pore
            r *= dim
            g *= dim
            b *= dim
            if freckle_chance > 0:
                var spot = _spots(
                    fx, fy, size, freckle_cell, freckle_chance, 53
                )
                r = _lerp(r, r * Float32(0.86), spot)
                g = _lerp(g, g * Float32(0.74), spot)
                b = _lerp(b, b * Float32(0.64), spot)
            var mole = _spots(fx, fy, size, mole_cell, 0.02, 67)
            r = _lerp(r, r * Float32(0.55), mole)
            g = _lerp(g, g * Float32(0.45), mole)
            b = _lerp(b, b * Float32(0.42), mole)
            pixels.append(_byte(r))
            pixels.append(_byte(g))
            pixels.append(_byte(b))
            pixels.append(255)
    return pixels^


def skin_relief_pixels(size: Int) raises -> List[UInt8]:
    """Return the RGBA bytes of a tiling height map of the skin's surface.

    White is high. Skin's surface is a net of fine furrows that cross in
    two directions and pores that sink at their crossings, over a gentle
    unevenness. Each channel holds the same height.

    Args:
        size: Width and height in texels, eight through 512.

    Returns:
        `size * size * 4` bytes, row by row from the top.

    Raises:
        Error: If `size` is out of range.
    """
    check_map_size(size, "skin relief")
    var pore_cell = max(3, size // 48)
    var pixels = List[UInt8](capacity=size * size * 4)
    var lines = Float32(max(4, size // 6))
    var tau = Float32(6.2831853)
    for y in range(size):  # pragma: no branch
        var fy = Float32(y) + Float32(0.5)
        for x in range(size):  # pragma: no branch
            var fx = Float32(x) + Float32(0.5)
            var u = fx / Float32(size)
            var v = fy / Float32(size)
            # Two families of furrows, wavy, crossing at about ninety
            # degrees. Whole numbers of waves keep the map tiling.
            var wobble = _fbm(fx, fy, size, 8, 2, 71)
            var one = cos(tau * (lines * (u + v) + 2 * wobble))
            var two = cos(tau * (lines * (u - v) + 2 * wobble))
            var furrow = max(Float32(0), one) + max(Float32(0), two)
            var pore = _spots(fx, fy, size, pore_cell, 0.7, 41)
            var broad = _fbm(fx, fy, size, 6, 3, 83)
            var height = (
                Float32(0.62)
                + Float32(0.10) * furrow
                - Float32(0.45) * pore
                + Float32(0.25) * broad
            )
            var level = _byte(height * 255)
            pixels.append(level)
            pixels.append(level)
            pixels.append(level)
            pixels.append(255)
    return pixels^


def skin_relief(size: Int = 128) raises -> Texture:
    """Return a tiling height map of the skin's pores and furrows.

    Use it as a bump map. It is linear data, not a color.

    Args:
        size: Width and height in texels, eight through 512.

    Returns:
        A linear texture that repeats in both directions.

    Raises:
        Error: If `size` is out of range.
    """
    return Texture(
        size,
        size,
        skin_relief_pixels(size),
        REPEAT,
        color_space=LINEAR,
        alpha=IGNORED,
    )


def iris_pixels(size: Int, genome: Genome) raises -> List[UInt8]:
    """Return the RGBA bytes of an eyeball's color map.

    `u` runs around the eye's axis and `v` from the front pole, at 0, to
    the back, at 1. The front holds the pupil, then the iris with its
    radial fibers, its collarette and its darker limbal ring, then the
    white sclera, faintly veined toward the back.

    Args:
        size: Width and height in texels, eight through 512.
        genome: Reads `IRIS_MELANIN`.

    Returns:
        `size * size * 4` bytes, row by row from the top.

    Raises:
        Error: If `size` is out of range or `genome` is not valid.
    """
    check_map_size(size, "eye")
    var iris = iris_tone(genome)
    var base = Tone(Float32(iris.r), Float32(iris.g), Float32(iris.b))
    var sclera = Tone(236, 230, 222)
    var pixels = List[UInt8](capacity=size * size * 4)
    for y in range(size):  # pragma: no branch
        # The image's top row is v = 1, the back of the eye.
        var v = 1 - (Float32(y) + Float32(0.5)) / Float32(size)
        for x in range(size):  # pragma: no branch
            var fx = Float32(x) + Float32(0.5)
            var fibers = _fbm(fx, Float32(y), size, 48, 2, 97, 2)
            var tone: Tone
            if v < EYE_PUPIL:
                tone = Tone(8, 8, 10)
            elif v < EYE_IRIS:
                var t = (v - EYE_PUPIL) / (EYE_IRIS - EYE_PUPIL)
                # Darker around the pupil, lighter in the middle, and a
                # dark limbal ring at the edge.
                var shade = (
                    1
                    + Float32(0.9) * fibers
                    - Float32(0.25) * (1 - _smooth(0.0, 0.25, t))
                    - Float32(0.55) * _smooth(0.78, 1.0, t)
                )
                var collarette = 1 - _smooth(0.0, 0.08, abs(t - 0.32))
                shade += Float32(0.18) * collarette
                tone = Tone(base.r * shade, base.g * shade, base.b * shade)
            else:
                var t = _smooth(EYE_IRIS, EYE_IRIS + 0.04, v)
                var vein = _smooth(
                    0.35, 0.5, _fbm(fx, Float32(y), size, 12, 3, 101)
                )
                var back = _smooth(0.3, 0.9, v)
                tone = sclera.mix(Tone(200, 120, 110), vein * back * 0.5)
                tone = Tone(
                    _lerp(base.r * 0.4, tone.r, t),
                    _lerp(base.g * 0.4, tone.g, t),
                    _lerp(base.b * 0.4, tone.b, t),
                )
            pixels.append(_byte(tone.r))
            pixels.append(_byte(tone.g))
            pixels.append(_byte(tone.b))
            pixels.append(255)
    return pixels^


# Where the pupil and the iris end, as `v` from the eye's front pole.
comptime EYE_PUPIL = Float32(0.06)
comptime EYE_IRIS = Float32(0.15)


def iris_albedo(size: Int = 64, genome: Genome = Genome()) raises -> Texture:
    """Return an eyeball's color map: pupil, iris and sclera.

    Args:
        size: Width and height in texels, eight through 512.
        genome: Reads `IRIS_MELANIN`.

    Returns:
        An sRGB texture for the geometry `eyeball_mesh` makes.

    Raises:
        Error: If `size` is out of range or `genome` is not valid.
    """
    return Texture(
        size, size, iris_pixels(size, genome), REPEAT, color_space=SRGB
    )


def hair_pixels(size: Int, genome: Genome) raises -> List[UInt8]:
    """Return the RGBA bytes of a tiling map of hair's strands.

    The strands run up and down the map: `v` is along them. Each column
    is a strand a little lighter or darker than its neighbors, with a
    slow wave, and the lighter strands catch the light.

    Args:
        size: Width and height in texels, eight through 512.
        genome: Reads the hair's genes.

    Returns:
        `size * size * 4` bytes, row by row from the top.

    Raises:
        Error: If `size` is out of range or `genome` is not valid.
    """
    check_map_size(size, "hair")
    var mean = hair_tone(genome)
    var base = Tone(Float32(mean.r), Float32(mean.g), Float32(mean.b))
    var pixels = List[UInt8](capacity=size * size * 4)
    for y in range(size):  # pragma: no branch
        var fy = Float32(y) + Float32(0.5)
        for x in range(size):  # pragma: no branch
            var fx = Float32(x) + Float32(0.5)
            # Strands: fine across, long along, and a slow sway.
            var sway = _fbm(fx, fy, size, 2, 2, 131) * Float32(6)
            var strand = _fbm(fx + sway, fy, size, 64, 3, 137, 2)
            var clump = _fbm(fx + sway, fy, size, 12, 2, 139, 2)
            var shade = 1 + Float32(1.1) * strand + Float32(0.5) * clump
            pixels.append(_byte(base.r * shade))
            pixels.append(_byte(base.g * shade))
            pixels.append(_byte(base.b * shade))
            pixels.append(255)
    return pixels^


def hair_albedo(size: Int = 128, genome: Genome = Genome()) raises -> Texture:
    """Return a tiling map of hair's strands in the color `genome` asks
    for.

    Args:
        size: Width and height in texels, eight through 512.
        genome: Reads `HAIR_MELANIN` and `HAIR_REDNESS`.

    Returns:
        An sRGB texture whose strands run along `v`.

    Raises:
        Error: If `size` is out of range or `genome` is not valid.
    """
    return Texture(
        size, size, hair_pixels(size, genome), REPEAT, color_space=SRGB
    )
