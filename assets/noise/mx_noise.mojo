# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Values of three.js 0.180's MaterialX noises, for `tests/test_nodes.mojo`.

three.js writes these noises in TSL, `src/nodes/materialx/lib/mx_noise.js`,
which runs only on a GPU. This file transcribes the functions the tests
check, line by line, in 32-bit floats and 32-bit unsigned integers, in the
same order of operations. Run it: `mojo run -I . assets/noise/mx_noise.mojo`.

Each product is formed in Float64, where two Float32 values multiply
exactly, and then rounded to Float32 with integer operations
(`tools/_float32.mojo`). A plain
Float32 multiply could be fused with the next sum into one rounding, and
the compiler can turn a narrowed Float64 product back into one. So every
operation rounds as a separate 32-bit operation does, as in the numpy
transcription that this file replaces.
"""

from std.math import floor

from tools._float32 import mul
from tools._python_float import python_repr


def rotl(x: UInt32, k: UInt32) -> UInt32:
    """Rotate left.

    Args:
        x: The word.
        k: The bits to rotate by, 1 to 31.

    Returns:
        The rotated word.
    """
    return (x << k) | (x >> (32 - k))


def bjmix(
    var a: UInt32, var b: UInt32, var c: UInt32
) -> Tuple[UInt32, UInt32, UInt32]:
    """Mix three words, as Bob Jenkins' `mix` does.

    Args:
        a: The first word.
        b: The second word.
        c: The third word.

    Returns:
        The mixed words.
    """
    a -= c
    a ^= rotl(c, 4)
    c += b
    b -= a
    b ^= rotl(a, 6)
    a += c
    c -= b
    c ^= rotl(b, 8)
    b += a
    a -= c
    a ^= rotl(c, 16)
    c += b
    b -= a
    b ^= rotl(a, 19)
    a += c
    c -= b
    c ^= rotl(b, 4)
    b += a
    return (a, b, c)


def bjfinal(var a: UInt32, var b: UInt32, var c: UInt32) -> UInt32:
    """Finish a hash, as Bob Jenkins' `final` does.

    Args:
        a: The first word.
        b: The second word.
        c: The third word.

    Returns:
        The hash.
    """
    c ^= b
    c -= rotl(b, 14)
    a ^= c
    a -= rotl(c, 11)
    b ^= a
    b -= rotl(a, 25)
    c ^= b
    c -= rotl(b, 16)
    a ^= c
    a -= rotl(c, 4)
    b ^= a
    b -= rotl(a, 14)
    c ^= b
    c -= rotl(b, 24)
    return c


def hash_int(xs: List[Int]) -> UInt32:
    """Hash one to five integers.

    Args:
        xs: The integers, taken modulo 2**32.

    Returns:
        The hash.
    """
    var seed = UInt32(0xDEADBEEF) + UInt32(len(xs) << 2) + 13
    var ints = List[UInt32]()
    for x in xs:
        ints.append(UInt32(x & 0xFFFFFFFF))
    if len(xs) == 1:
        return bjfinal(seed + ints[0], seed, seed)
    var a = seed + ints[0]
    var b = seed + ints[1]
    var c = seed + ints[2] if len(xs) >= 3 else seed
    if len(xs) <= 3:
        return bjfinal(a, b, c)
    var mixed = bjmix(a, b, c)
    a = mixed[0] + ints[3]
    b = mixed[1]
    c = mixed[2]
    if len(xs) == 5:
        b += ints[4]
    return bjfinal(a, b, c)


def bits_to_01(bits: UInt32) -> Float32:
    """Map a hash to [0, 1].

    Args:
        bits: The hash.

    Returns:
        The value.
    """
    return Float32(bits) / Float32(4294967295)


def floorfrac(x: Float64) -> Tuple[Float32, Int]:
    """Split a coordinate into its fraction and its floor.

    Args:
        x: The coordinate, rounded to Float32 first.

    Returns:
        The fraction and the floor.
    """
    var value = Float32(x)
    var whole = Int(floor(value))
    return (value - Float32(whole), whole)


def fade(t: Float32) -> Float32:
    """Return Perlin's quintic fade.

    Args:
        t: The fraction.

    Returns:
        6t^5 - 15t^4 + 10t^3.
    """
    return mul(
        mul(mul(t, t), t),
        mul(t, mul(t, Float32(6.0)) - Float32(15.0)) + Float32(10.0),
    )


def gradient2(var h: Int, x: Float32, y: Float32) -> Float32:
    """Return a 2D gradient's dot product.

    Args:
        h: The hash byte.
        x: The first offset.
        y: The second offset.

    Returns:
        The dot product.
    """
    h &= 7
    var uu = x if h < 4 else y
    var vv = mul(Float32(2.0), y if h < 4 else x)
    uu = -uu if h & 1 else uu
    vv = -vv if h & 2 else vv
    return uu + vv


def gradient3(var h: Int, x: Float32, y: Float32, z: Float32) -> Float32:
    """Return a 3D gradient's dot product.

    Args:
        h: The hash byte.
        x: The first offset.
        y: The second offset.
        z: The third offset.

    Returns:
        The dot product.
    """
    h &= 15
    var uu = x if h < 8 else y
    var vv = y if h < 4 else (x if h == 12 or h == 14 else z)
    uu = -uu if h & 1 else uu
    vv = -vv if h & 2 else vv
    return uu + vv


def bilerp(
    v0: Float32, v1: Float32, v2: Float32, v3: Float32, s: Float32, t: Float32
) -> Float32:
    """Interpolate four corners.

    Args:
        v0: The corner at (0, 0).
        v1: The corner at (1, 0).
        v2: The corner at (0, 1).
        v3: The corner at (1, 1).
        s: The first weight.
        t: The second weight.

    Returns:
        The interpolated value.
    """
    var s1 = Float32(1.0) - s
    return mul(Float32(1.0) - t, mul(v0, s1) + mul(v1, s)) + mul(
        t, mul(v2, s1) + mul(v3, s)
    )


def trilerp(v: List[Float32], s: Float32, t: Float32, r: Float32) -> Float32:
    """Interpolate eight corners.

    Args:
        v: The corners, x fastest, then y, then z.
        s: The first weight.
        t: The second weight.
        r: The third weight.

    Returns:
        The interpolated value.
    """
    var s1 = Float32(1.0) - s
    var t1 = Float32(1.0) - t
    var r1 = Float32(1.0) - r
    var near = mul(t1, mul(v[0], s1) + mul(v[1], s)) + mul(
        t, mul(v[2], s1) + mul(v[3], s)
    )
    var far = mul(t1, mul(v[4], s1) + mul(v[5], s)) + mul(
        t, mul(v[6], s1) + mul(v[7], s)
    )
    return mul(r1, near) + mul(r, far)


def perlin_vec3(p: List[Float64]) -> List[Float32]:
    """Return three channels of Perlin noise in 2D or 3D.

    Args:
        p: Two or three coordinates.

    Returns:
        The three channels.
    """
    var out = List[Float32]()
    if len(p) == 2:
        var x = floorfrac(p[0])
        var y = floorfrac(p[1])
        var uu = fade(x[0])
        var vv = fade(y[0])
        for k in range(3):
            var g = List[Float32]()
            for corner in [(0, 0), (1, 0), (0, 1), (1, 1)]:
                var h = Int(hash_int([x[1] + corner[0], y[1] + corner[1]]))
                g.append(
                    gradient2(
                        (h >> (8 * k)) & 0xFF,
                        x[0] - Float32(corner[0]),
                        y[0] - Float32(corner[1]),
                    )
                )
            out.append(
                mul(Float32(0.6616), bilerp(g[0], g[1], g[2], g[3], uu, vv))
            )
        return out^
    var x = floorfrac(p[0])
    var y = floorfrac(p[1])
    var z = floorfrac(p[2])
    var uu = fade(x[0])
    var vv = fade(y[0])
    var ww = fade(z[0])
    for k in range(3):
        var v = List[Float32]()
        for dz in range(2):
            for dy in range(2):
                for dx in range(2):
                    var h = Int(hash_int([x[1] + dx, y[1] + dy, z[1] + dz]))
                    v.append(
                        gradient3(
                            (h >> (8 * k)) & 0xFF,
                            x[0] - Float32(dx),
                            y[0] - Float32(dy),
                            z[0] - Float32(dz),
                        )
                    )
        out.append(mul(Float32(0.9820), trilerp(v, uu, vv, ww)))
    return out^


def _floors(p: List[Float64]) -> List[Int]:
    """Return each coordinate's Float32 floor."""
    var out = List[Int]()
    for x in p:
        out.append(Int(floor(Float32(x))))
    return out^


def cell_float(p: List[Float64]) -> Float32:
    """Return one value for the cell that holds a point.

    Args:
        p: One to four coordinates.

    Returns:
        The cell's value in [0, 1].
    """
    return bits_to_01(hash_int(_floors(p)))


def cell_vec3(p: List[Float64]) -> List[Float32]:
    """Return three values for the cell that holds a point.

    Args:
        p: One to four coordinates.

    Returns:
        The cell's three values in [0, 1].
    """
    var out = List[Float32]()
    for k in range(3):
        var ints = _floors(p)
        ints.append(k)
        out.append(bits_to_01(hash_int(ints)))
    return out^


def worley(p: List[Float64], jitter: Float64, width: Int) -> List[Float32]:
    """Return the nearest squared distances to jittered cell points.

    Args:
        p: Two or three coordinates.
        jitter: The jitter, 0 to 1.
        width: How many distances to keep: 1, 2 or 3.

    Returns:
        The smallest `width` squared distances, nearest first.
    """
    var ints = List[Int]()
    var local = List[Float32]()
    for x in p:
        var split = floorfrac(x)
        ints.append(split[1])
        local.append(split[0])
    var best = List[Float32](length=width, fill=Float32(1e6))
    var count = 1
    for _ in p:
        count *= 3
    for index in range(count):
        # The last offset changes fastest, as in itertools.product.
        var offsets = List[Int](length=len(p), fill=0)
        var rest = index
        for axis in range(len(p) - 1, -1, -1):
            offsets[axis] = rest % 3 - 1
            rest //= 3
        var cell = List[Float64]()
        for axis in range(len(p)):
            cell.append(Float64(Float32(offsets[axis] + ints[axis])))
        var tmp = cell_vec3(cell)
        var dist = Float32(0)
        for axis in range(len(p)):
            var off = mul(tmp[axis] - Float32(0.5), Float32(jitter)) + Float32(
                0.5
            )
            var d = (Float32(offsets[axis]) + off) - local[axis]
            dist = dist + mul(d, d)
        if dist < best[0]:
            best.insert(0, dist)
            _ = best.pop()
        elif width > 1 and dist < best[1]:
            best.insert(1, dist)
            _ = best.pop()
        elif width > 2 and dist < best[2]:
            best[2] = dist
    return best^


def _list(values: List[Float64]) raises -> String:
    """Return a list of floats as Python prints it."""
    var words = List[String]()
    for value in values:
        words.append(python_repr(value))
    return "[" + ", ".join(words) + "]"


def _list32(values: List[Float32]) raises -> String:
    """Return a list of Float32 values, widened, as Python prints it."""
    var wide = List[Float64]()
    for value in values:
        wide.append(Float64(value))
    return _list(wide)


def report() raises -> String:
    """Return the values the tests check, one line each.

    Returns:
        The lines, each ended by a newline.

    Raises:
        Error: Never; float text cannot fail for finite values.
    """
    var out = String()
    var points: List[List[Float64]] = [
        [0.3, 0.7],
        [-1.25, 2.5],
        [0.3, 0.7, 0.2],
        [3.1, -2.3, 5.9],
    ]
    for p in points:
        out += "perlin_vec3 " + _list(p) + " " + _list32(perlin_vec3(p)) + "\n"
    var cells: List[List[Float64]] = [
        [0.3],
        [-1.25, 2.5],
        [0.3, 0.7, 0.2],
        [3.1, -2.3, 5.9, -0.4],
    ]
    for p in cells:
        out += (
            "cell_float "
            + _list(p)
            + " "
            + python_repr(Float64(cell_float(p)))
            + " cell_vec3 "
            + _list32(cell_vec3(p))
            + "\n"
        )
    var worleys: List[List[Float64]] = [[0.3, 0.7], [-1.25, 2.5, 0.6]]
    for p in worleys:
        for jitter in [1.0, 0.5]:
            for width in [1, 2, 3]:
                out += (
                    "worley "
                    + _list(p)
                    + " "
                    + python_repr(jitter)
                    + " "
                    + String(width)
                    + " "
                    + _list32(worley(p, jitter, width))
                    + "\n"
                )
    return out^


def main() raises:
    print(report(), end="")
