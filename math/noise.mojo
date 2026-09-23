# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Two noise functions, from three.js `examples/jsm/math/ImprovedNoise.js`
and `examples/jsm/math/SimplexNoise.js`.

Noise is a smooth random field: close points get close values, and far
points get unrelated values. A terrain height, a cloud or a marble vein is
noise sampled on a grid.

`ImprovedNoise` is Ken Perlin's 2002 gradient noise in three dimensions. Its
permutation table is fixed, so it has no seed and every call anywhere gives
the same value. `SimplexNoise` is Stefan Gustavson's simplex noise in two,
three and four dimensions. Its permutation table comes from a random
generator, so the seed picks the field.

Both compute in `Float64`, as JavaScript does, and give three.js's values
bit for bit: the tests check them against values that three.js calculated.
A lattice coordinate is reduced modulo 256 without a conversion to a 32-bit
integer, which gives JavaScript's `& 255` for every finite input.

**Differences from three.js.** A coordinate that is not finite is refused:
three.js returns `NaN` for it. `SimplexNoise` takes a `SeededRandom`, three.js's
`MathUtils.seededRandom` generator. three.js takes any object with a
`random()` method and uses `Math.random` by default, which cannot be seeded.
"""

from math.utils import SeededRandom
from std.benchmark import black_box
from std.math import floor, isfinite, sqrt

# Ken Perlin's permutation of 0 to 255. three.js doubles it to 512 entries so
# that an index up to 511 needs no wrap; here the index is wrapped instead,
# which reads the same entry.
comptime _PERM = SIMD[DType.uint8, 256](
    151,
    160,
    137,
    91,
    90,
    15,
    131,
    13,
    201,
    95,
    96,
    53,
    194,
    233,
    7,
    225,
    140,
    36,
    103,
    30,
    69,
    142,
    8,
    99,
    37,
    240,
    21,
    10,
    23,
    190,
    6,
    148,
    247,
    120,
    234,
    75,
    0,
    26,
    197,
    62,
    94,
    252,
    219,
    203,
    117,
    35,
    11,
    32,
    57,
    177,
    33,
    88,
    237,
    149,
    56,
    87,
    174,
    20,
    125,
    136,
    171,
    168,
    68,
    175,
    74,
    165,
    71,
    134,
    139,
    48,
    27,
    166,
    77,
    146,
    158,
    231,
    83,
    111,
    229,
    122,
    60,
    211,
    133,
    230,
    220,
    105,
    92,
    41,
    55,
    46,
    245,
    40,
    244,
    102,
    143,
    54,
    65,
    25,
    63,
    161,
    1,
    216,
    80,
    73,
    209,
    76,
    132,
    187,
    208,
    89,
    18,
    169,
    200,
    196,
    135,
    130,
    116,
    188,
    159,
    86,
    164,
    100,
    109,
    198,
    173,
    186,
    3,
    64,
    52,
    217,
    226,
    250,
    124,
    123,
    5,
    202,
    38,
    147,
    118,
    126,
    255,
    82,
    85,
    212,
    207,
    206,
    59,
    227,
    47,
    16,
    58,
    17,
    182,
    189,
    28,
    42,
    223,
    183,
    170,
    213,
    119,
    248,
    152,
    2,
    44,
    154,
    163,
    70,
    221,
    153,
    101,
    155,
    167,
    43,
    172,
    9,
    129,
    22,
    39,
    253,
    19,
    98,
    108,
    110,
    79,
    113,
    224,
    232,
    178,
    185,
    112,
    104,
    218,
    246,
    97,
    228,
    251,
    34,
    242,
    193,
    238,
    210,
    144,
    12,
    191,
    179,
    162,
    241,
    81,
    51,
    145,
    235,
    249,
    14,
    239,
    107,
    49,
    192,
    214,
    31,
    181,
    199,
    106,
    157,
    184,
    84,
    204,
    176,
    115,
    121,
    50,
    45,
    127,
    4,
    150,
    254,
    138,
    236,
    205,
    93,
    222,
    114,
    67,
    29,
    24,
    72,
    243,
    141,
    128,
    195,
    78,
    66,
    215,
    61,
    156,
    180,
)

# SimplexNoise's `grad3`: the twelve midpoints of a cube's edges, three
# numbers each, padded to a power of two.
comptime _GRAD3 = SIMD[DType.int8, 64](
    1,
    1,
    0,
    -1,
    1,
    0,
    1,
    -1,
    0,
    -1,
    -1,
    0,
    1,
    0,
    1,
    -1,
    0,
    1,
    1,
    0,
    -1,
    -1,
    0,
    -1,
    0,
    1,
    1,
    0,
    -1,
    1,
    0,
    1,
    -1,
    0,
    -1,
    -1,
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

# SimplexNoise's `grad4`: the 32 midpoints of a tesseract's edges.
comptime _GRAD4 = SIMD[DType.int8, 128](
    0,
    1,
    1,
    1,
    0,
    1,
    1,
    -1,
    0,
    1,
    -1,
    1,
    0,
    1,
    -1,
    -1,
    0,
    -1,
    1,
    1,
    0,
    -1,
    1,
    -1,
    0,
    -1,
    -1,
    1,
    0,
    -1,
    -1,
    -1,
    1,
    0,
    1,
    1,
    1,
    0,
    1,
    -1,
    1,
    0,
    -1,
    1,
    1,
    0,
    -1,
    -1,
    -1,
    0,
    1,
    1,
    -1,
    0,
    1,
    -1,
    -1,
    0,
    -1,
    1,
    -1,
    0,
    -1,
    -1,
    1,
    1,
    0,
    1,
    1,
    1,
    0,
    -1,
    1,
    -1,
    0,
    1,
    1,
    -1,
    0,
    -1,
    -1,
    1,
    0,
    1,
    -1,
    1,
    0,
    -1,
    -1,
    -1,
    0,
    1,
    -1,
    -1,
    0,
    -1,
    1,
    1,
    1,
    0,
    1,
    1,
    -1,
    0,
    1,
    -1,
    1,
    0,
    1,
    -1,
    -1,
    0,
    -1,
    1,
    1,
    0,
    -1,
    1,
    -1,
    0,
    -1,
    -1,
    1,
    0,
    -1,
    -1,
    -1,
    0,
)

# SimplexNoise's `simplex`: for each of the 64 orderings of four
# coordinates, which corner of the 4D simplex to visit next.
comptime _SIMPLEX = SIMD[DType.uint8, 256](
    0,
    1,
    2,
    3,
    0,
    1,
    3,
    2,
    0,
    0,
    0,
    0,
    0,
    2,
    3,
    1,
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
    1,
    2,
    3,
    0,
    0,
    2,
    1,
    3,
    0,
    0,
    0,
    0,
    0,
    3,
    1,
    2,
    0,
    3,
    2,
    1,
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
    1,
    3,
    2,
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
    1,
    2,
    0,
    3,
    0,
    0,
    0,
    0,
    1,
    3,
    0,
    2,
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
    2,
    3,
    0,
    1,
    2,
    3,
    1,
    0,
    1,
    0,
    2,
    3,
    1,
    0,
    3,
    2,
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
    2,
    0,
    3,
    1,
    0,
    0,
    0,
    0,
    2,
    1,
    3,
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
    2,
    0,
    1,
    3,
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
    3,
    0,
    1,
    2,
    3,
    0,
    2,
    1,
    0,
    0,
    0,
    0,
    3,
    1,
    2,
    0,
    2,
    1,
    0,
    3,
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
    3,
    1,
    0,
    2,
    0,
    0,
    0,
    0,
    3,
    2,
    0,
    1,
    3,
    2,
    1,
    0,
)


def _mul(a: Float64, b: Float64) -> Float64:
    """Return a product rounded on its own, before any sum uses it.

    Mojo contracts `a * b + c` into one fused multiply-add by default, and
    that rounds once where JavaScript rounds twice. The last bit then
    differs from three.js. The barrier keeps the product a value of its own.
    A product by zero, one or a power of two is exact and needs none.

    Args:
        a: One factor.
        b: The other.

    Returns:
        The rounded product.
    """
    return black_box(a * b)


def _check_finite(value: Float64) raises:
    """Refuse a coordinate that is not a finite number.

    Args:
        value: The coordinate.

    Raises:
        Error: If it is infinite or not a number.
    """
    if not isfinite(value):
        raise Error("A noise coordinate must be a finite number")


def _wrap(cell: Float64) -> Int:
    """Return a whole number modulo 256, JavaScript's `cell & 255`.

    The arithmetic is exact for every finite whole `Float64`: the division
    and the product are by a power of two, and the difference of two
    numbers this close is exact. A conversion to `Int` first would overflow
    past 2 to the 63rd.

    Args:
        cell: A whole number, the floor of a coordinate.

    Returns:
        A number from 0 to 255.
    """
    return Int(cell - 256.0 * floor(cell / 256.0))


def _perm(index: Int) -> Int:
    """Return an entry of Perlin's doubled permutation table.

    Args:
        index: A position from 0 to 511.

    Returns:
        The entry.
    """
    return Int(_PERM[index & 255])


def _fade(t: Float64) -> Float64:
    """Return Perlin's quintic ease curve, `6t^5 - 15t^4 + 10t^3`.

    Args:
        t: A fraction from zero to one.

    Returns:
        The eased fraction.
    """
    return t * t * t * (_mul(t, _mul(t, 6) - 15) + 10)


def _lerp(x: Float64, y: Float64, t: Float64) -> Float64:
    """Return three.js's `MathUtils.lerp`, `(1 - t) * x + t * y`.

    Args:
        x: The start.
        y: The end.
        t: The fraction.

    Returns:
        The mix.
    """
    return _mul(1 - t, x) + _mul(t, y)


def _grad(hash: Int, x: Float64, y: Float64, z: Float64) -> Float64:
    """Return the dot product of a hashed gradient and an offset.

    Args:
        hash: A permutation entry. Its low four bits pick the gradient.
        x: The offset along x.
        y: The offset along y.
        z: The offset along z.

    Returns:
        The dot product.
    """
    var h = hash & 15
    var u = x if h < 8 else y
    var v = y if h < 4 else (x if h == 12 or h == 14 else z)
    return (u if (h & 1) == 0 else -u) + (v if (h & 2) == 0 else -v)


@fieldwise_init
struct ImprovedNoise(ImplicitlyCopyable):
    """Ken Perlin's improved noise in three dimensions. three.js:
    `ImprovedNoise`."""

    def noise(self, x: Float64, y: Float64, z: Float64) raises -> Float64:
        """Return the noise at a point. three.js: `noise`.

        The value is zero at every whole-number point, and it is about in
        the range from -1 to 1 everywhere.

        Args:
            x: The x coordinate.
            y: The y coordinate.
            z: The z coordinate.

        Returns:
            The noise value.

        Raises:
            Error: If a coordinate is not finite.
        """
        _check_finite(x)
        _check_finite(y)
        _check_finite(z)
        var floor_x = floor(x)
        var floor_y = floor(y)
        var floor_z = floor(z)
        var cx = _wrap(floor_x)
        var cy = _wrap(floor_y)
        var cz = _wrap(floor_z)
        var fx = x - floor_x
        var fy = y - floor_y
        var fz = z - floor_z
        var x_minus1 = fx - 1
        var y_minus1 = fy - 1
        var z_minus1 = fz - 1
        var u = _fade(fx)
        var v = _fade(fy)
        var w = _fade(fz)
        var a = _perm(cx) + cy
        var aa = _perm(a) + cz
        var ab = _perm(a + 1) + cz
        var b = _perm(cx + 1) + cy
        var ba = _perm(b) + cz
        var bb = _perm(b + 1) + cz
        return _lerp(
            _lerp(
                _lerp(
                    _grad(_perm(aa), fx, fy, fz),
                    _grad(_perm(ba), x_minus1, fy, fz),
                    u,
                ),
                _lerp(
                    _grad(_perm(ab), fx, y_minus1, fz),
                    _grad(_perm(bb), x_minus1, y_minus1, fz),
                    u,
                ),
                v,
            ),
            _lerp(
                _lerp(
                    _grad(_perm(aa + 1), fx, fy, z_minus1),
                    _grad(_perm(ba + 1), x_minus1, fy, z_minus1),
                    u,
                ),
                _lerp(
                    _grad(_perm(ab + 1), fx, y_minus1, z_minus1),
                    _grad(_perm(bb + 1), x_minus1, y_minus1, z_minus1),
                    u,
                ),
                v,
            ),
            w,
        )


def _corner2(t_in: Float64, gradient: Int, x: Float64, y: Float64) -> Float64:
    """Return one corner's share of 2D simplex noise.

    Args:
        t_in: The falloff, `0.5 - x^2 - y^2`.
        gradient: Which of `grad3` to use.
        x: The offset from the corner along x.
        y: The offset along y.

    Returns:
        Zero past the falloff, or the weighted dot product.
    """
    if t_in < 0:
        return 0.0
    var t = t_in * t_in
    var g = gradient * 3
    return t * t * (Float64(_GRAD3[g]) * x + Float64(_GRAD3[g + 1]) * y)


def _corner3(
    t_in: Float64, gradient: Int, x: Float64, y: Float64, z: Float64
) -> Float64:
    """Return one corner's share of 3D simplex noise.

    Args:
        t_in: The falloff, `0.6 - x^2 - y^2 - z^2`.
        gradient: Which of `grad3` to use.
        x: The offset from the corner along x.
        y: The offset along y.
        z: The offset along z.

    Returns:
        Zero past the falloff, or the weighted dot product.
    """
    if t_in < 0:
        return 0.0
    var t = t_in * t_in
    var g = gradient * 3
    return (
        t
        * t
        * (
            Float64(_GRAD3[g]) * x
            + Float64(_GRAD3[g + 1]) * y
            + Float64(_GRAD3[g + 2]) * z
        )
    )


def _corner4(
    t_in: Float64,
    gradient: Int,
    x: Float64,
    y: Float64,
    z: Float64,
    w: Float64,
) -> Float64:
    """Return one corner's share of 4D simplex noise.

    Args:
        t_in: The falloff, `0.6 - x^2 - y^2 - z^2 - w^2`.
        gradient: Which of `grad4` to use.
        x: The offset from the corner along x.
        y: The offset along y.
        z: The offset along z.
        w: The offset along w.

    Returns:
        Zero past the falloff, or the weighted dot product.
    """
    if t_in < 0:
        return 0.0
    var t = t_in * t_in
    var g = gradient * 4
    return (
        t
        * t
        * (
            Float64(_GRAD4[g]) * x
            + Float64(_GRAD4[g + 1]) * y
            + Float64(_GRAD4[g + 2]) * z
            + Float64(_GRAD4[g + 3]) * w
        )
    )


def _step(value: Int, threshold: Int) -> Int:
    """Return one if a simplex rank reaches a threshold, else zero.

    Args:
        value: An entry of the `simplex` table.
        threshold: The rank to reach.

    Returns:
        One or zero.
    """
    return 1 if value >= threshold else 0


struct SimplexNoise(Copyable, Movable):
    """Stefan Gustavson's simplex noise in two, three and four dimensions.
    three.js: `SimplexNoise`."""

    # three.js's `perm`: 256 random numbers from 0 to 255, doubled.
    var perm: List[Int]

    def __init__(out self, mut random: SeededRandom):
        """Create the noise, drawing its permutation from a generator.

        The generator is called 256 times, in three.js's order, so a
        generator seeded as three.js's `MathUtils.seededRandom` is seeded
        gives three.js's field.

        Args:
            random: The generator. It is advanced by 256 numbers.
        """
        var p = List[Int]()
        for _ in range(256):  # pragma: no branch
            p.append(Int(floor(random.next() * 256)))
        self.perm = List[Int]()
        for i in range(512):  # pragma: no branch
            self.perm.append(p[i & 255])

    def noise(self, xin: Float64, yin: Float64) raises -> Float64:
        """Return the 2D noise at a point. three.js: `noise`.

        Args:
            xin: The x coordinate.
            yin: The y coordinate.

        Returns:
            The noise value, in the range from -1 to 1.

        Raises:
            Error: If a coordinate is not finite.
        """
        _check_finite(xin)
        _check_finite(yin)
        var f2 = 0.5 * (sqrt(3.0) - 1.0)
        var s = _mul(xin + yin, f2)
        var i = floor(xin + s)
        var j = floor(yin + s)
        var g2 = (3.0 - sqrt(3.0)) / 6.0
        var t = _mul(i + j, g2)
        var x0 = xin - (i - t)
        var y0 = yin - (j - t)
        var i1 = 0
        var j1 = 1
        if x0 > y0:
            i1 = 1
            j1 = 0
        var x1 = x0 - Float64(i1) + g2
        var y1 = y0 - Float64(j1) + g2
        var x2 = x0 - 1.0 + _mul(2.0, g2)
        var y2 = y0 - 1.0 + _mul(2.0, g2)
        var ii = _wrap(i)
        var jj = _wrap(j)
        ref perm = self.perm
        var gi0 = perm[ii + perm[jj]] % 12
        var gi1 = perm[ii + i1 + perm[jj + j1]] % 12
        var gi2 = perm[ii + 1 + perm[jj + 1]] % 12
        var n0 = _corner2(0.5 - _mul(x0, x0) - _mul(y0, y0), gi0, x0, y0)
        var n1 = _corner2(0.5 - _mul(x1, x1) - _mul(y1, y1), gi1, x1, y1)
        var n2 = _corner2(0.5 - _mul(x2, x2) - _mul(y2, y2), gi2, x2, y2)
        return 70.0 * (n0 + n1 + n2)

    def noise3d(
        self, xin: Float64, yin: Float64, zin: Float64
    ) raises -> Float64:
        """Return the 3D noise at a point. three.js: `noise3d`.

        Args:
            xin: The x coordinate.
            yin: The y coordinate.
            zin: The z coordinate.

        Returns:
            The noise value, just inside the range from -1 to 1.

        Raises:
            Error: If a coordinate is not finite.
        """
        _check_finite(xin)
        _check_finite(yin)
        _check_finite(zin)
        var f3 = 1.0 / 3.0
        var s = _mul(xin + yin + zin, f3)
        var i = floor(xin + s)
        var j = floor(yin + s)
        var k = floor(zin + s)
        var g3 = 1.0 / 6.0
        var t = _mul(i + j + k, g3)
        var x0 = xin - (i - t)
        var y0 = yin - (j - t)
        var z0 = zin - (k - t)
        # Which of the six tetrahedra of the skewed cube holds the point:
        # the corners are visited in the order of the offsets, largest
        # first.
        var i1: Int
        var j1: Int
        var k1: Int
        var i2: Int
        var j2: Int
        var k2: Int
        if x0 >= y0:
            if y0 >= z0:
                i1 = 1
                j1 = 0
                k1 = 0
                i2 = 1
                j2 = 1
                k2 = 0
            elif x0 >= z0:
                i1 = 1
                j1 = 0
                k1 = 0
                i2 = 1
                j2 = 0
                k2 = 1
            else:
                i1 = 0
                j1 = 0
                k1 = 1
                i2 = 1
                j2 = 0
                k2 = 1
        else:
            if y0 < z0:
                i1 = 0
                j1 = 0
                k1 = 1
                i2 = 0
                j2 = 1
                k2 = 1
            elif x0 < z0:
                i1 = 0
                j1 = 1
                k1 = 0
                i2 = 0
                j2 = 1
                k2 = 1
            else:
                i1 = 0
                j1 = 1
                k1 = 0
                i2 = 1
                j2 = 1
                k2 = 0
        var x1 = x0 - Float64(i1) + g3
        var y1 = y0 - Float64(j1) + g3
        var z1 = z0 - Float64(k1) + g3
        var x2 = x0 - Float64(i2) + _mul(2.0, g3)
        var y2 = y0 - Float64(j2) + _mul(2.0, g3)
        var z2 = z0 - Float64(k2) + _mul(2.0, g3)
        var x3 = x0 - 1.0 + _mul(3.0, g3)
        var y3 = y0 - 1.0 + _mul(3.0, g3)
        var z3 = z0 - 1.0 + _mul(3.0, g3)
        var ii = _wrap(i)
        var jj = _wrap(j)
        var kk = _wrap(k)
        ref perm = self.perm
        var gi0 = perm[ii + perm[jj + perm[kk]]] % 12
        var gi1 = perm[ii + i1 + perm[jj + j1 + perm[kk + k1]]] % 12
        var gi2 = perm[ii + i2 + perm[jj + j2 + perm[kk + k2]]] % 12
        var gi3 = perm[ii + 1 + perm[jj + 1 + perm[kk + 1]]] % 12
        var n0 = _corner3(
            0.6 - _mul(x0, x0) - _mul(y0, y0) - _mul(z0, z0), gi0, x0, y0, z0
        )
        var n1 = _corner3(
            0.6 - _mul(x1, x1) - _mul(y1, y1) - _mul(z1, z1), gi1, x1, y1, z1
        )
        var n2 = _corner3(
            0.6 - _mul(x2, x2) - _mul(y2, y2) - _mul(z2, z2), gi2, x2, y2, z2
        )
        var n3 = _corner3(
            0.6 - _mul(x3, x3) - _mul(y3, y3) - _mul(z3, z3), gi3, x3, y3, z3
        )
        return 32.0 * (n0 + n1 + n2 + n3)

    def noise4d(
        self, x: Float64, y: Float64, z: Float64, w: Float64
    ) raises -> Float64:
        """Return the 4D noise at a point. three.js: `noise4d`.

        Args:
            x: The x coordinate.
            y: The y coordinate.
            z: The z coordinate.
            w: The w coordinate.

        Returns:
            The noise value, in the range from -1 to 1.

        Raises:
            Error: If a coordinate is not finite.
        """
        _check_finite(x)
        _check_finite(y)
        _check_finite(z)
        _check_finite(w)
        var f4 = (sqrt(5.0) - 1.0) / 4.0
        var g4 = (5.0 - sqrt(5.0)) / 20.0
        var s = _mul(x + y + z + w, f4)
        var i = floor(x + s)
        var j = floor(y + s)
        var k = floor(z + s)
        var l = floor(w + s)
        var t = _mul(i + j + k + l, g4)
        var x0 = x - (i - t)
        var y0 = y - (j - t)
        var z0 = z - (k - t)
        var w0 = w - (l - t)
        # Six comparisons make an index into the table of orderings.
        var c = (
            (32 if x0 > y0 else 0)
            + (16 if x0 > z0 else 0)
            + (8 if y0 > z0 else 0)
            + (4 if x0 > w0 else 0)
            + (2 if y0 > w0 else 0)
            + (1 if z0 > w0 else 0)
        )
        var s0 = Int(_SIMPLEX[c * 4])
        var s1 = Int(_SIMPLEX[c * 4 + 1])
        var s2 = Int(_SIMPLEX[c * 4 + 2])
        var s3 = Int(_SIMPLEX[c * 4 + 3])
        var i1 = _step(s0, 3)
        var j1 = _step(s1, 3)
        var k1 = _step(s2, 3)
        var l1 = _step(s3, 3)
        var i2 = _step(s0, 2)
        var j2 = _step(s1, 2)
        var k2 = _step(s2, 2)
        var l2 = _step(s3, 2)
        var i3 = _step(s0, 1)
        var j3 = _step(s1, 1)
        var k3 = _step(s2, 1)
        var l3 = _step(s3, 1)
        var x1 = x0 - Float64(i1) + g4
        var y1 = y0 - Float64(j1) + g4
        var z1 = z0 - Float64(k1) + g4
        var w1 = w0 - Float64(l1) + g4
        var x2 = x0 - Float64(i2) + _mul(2.0, g4)
        var y2 = y0 - Float64(j2) + _mul(2.0, g4)
        var z2 = z0 - Float64(k2) + _mul(2.0, g4)
        var w2 = w0 - Float64(l2) + _mul(2.0, g4)
        var x3 = x0 - Float64(i3) + _mul(3.0, g4)
        var y3 = y0 - Float64(j3) + _mul(3.0, g4)
        var z3 = z0 - Float64(k3) + _mul(3.0, g4)
        var w3 = w0 - Float64(l3) + _mul(3.0, g4)
        var x4 = x0 - 1.0 + _mul(4.0, g4)
        var y4 = y0 - 1.0 + _mul(4.0, g4)
        var z4 = z0 - 1.0 + _mul(4.0, g4)
        var w4 = w0 - 1.0 + _mul(4.0, g4)
        var ii = _wrap(i)
        var jj = _wrap(j)
        var kk = _wrap(k)
        var ll = _wrap(l)
        ref perm = self.perm
        var gi0 = perm[ii + perm[jj + perm[kk + perm[ll]]]] % 32
        var gi1 = (
            perm[ii + i1 + perm[jj + j1 + perm[kk + k1 + perm[ll + l1]]]] % 32
        )
        var gi2 = (
            perm[ii + i2 + perm[jj + j2 + perm[kk + k2 + perm[ll + l2]]]] % 32
        )
        var gi3 = (
            perm[ii + i3 + perm[jj + j3 + perm[kk + k3 + perm[ll + l3]]]] % 32
        )
        var gi4 = perm[ii + 1 + perm[jj + 1 + perm[kk + 1 + perm[ll + 1]]]] % 32
        var n0 = _corner4(
            0.6 - _mul(x0, x0) - _mul(y0, y0) - _mul(z0, z0) - _mul(w0, w0),
            gi0,
            x0,
            y0,
            z0,
            w0,
        )
        var n1 = _corner4(
            0.6 - _mul(x1, x1) - _mul(y1, y1) - _mul(z1, z1) - _mul(w1, w1),
            gi1,
            x1,
            y1,
            z1,
            w1,
        )
        var n2 = _corner4(
            0.6 - _mul(x2, x2) - _mul(y2, y2) - _mul(z2, z2) - _mul(w2, w2),
            gi2,
            x2,
            y2,
            z2,
            w2,
        )
        var n3 = _corner4(
            0.6 - _mul(x3, x3) - _mul(y3, y3) - _mul(z3, z3) - _mul(w3, w3),
            gi3,
            x3,
            y3,
            z3,
            w3,
        )
        var n4 = _corner4(
            0.6 - _mul(x4, x4) - _mul(y4, y4) - _mul(z4, z4) - _mul(w4, w4),
            gi4,
            x4,
            y4,
            z4,
            w4,
        )
        return 27.0 * (n0 + n1 + n2 + n3 + n4)
