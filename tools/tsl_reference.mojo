# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Values of three.js r186's TSL functions, for `tests/test_tsl_*.mojo`.

three.js writes these functions in TSL, which runs only on a GPU. This file
transcribes the ones the tests check, line by line, in 32-bit floats and
32-bit unsigned integers, in the same order of operations:

- `src/nodes/math/Hash.js`, `TriNoise3D.js` and the packings;
- `examples/jsm/tsl/math/curlNoise.js` and `voronoiNoise.js`;
- `examples/jsm/tsl/utils/RNoise.js` and `SpecularHelpers.js`.

Run it: `mojo run -I . tools/tsl_reference.mojo`. It prints the same
text as the numpy transcription that it replaces.

Each Float32 product is formed in Float64 and rounded once with integer
operations (`tools/_float32.mojo`), so no build can fuse it into a
multiply-add. Sums, differences, quotients and square roots are plain
Float32 operations, which round once.

numpy 2.5 does not use the C library for float32 `sin`, `cos`, `log` and
`power` on an x86-64 CPU with AVX-512. Its results differ from `sinf`,
`cosf` and `logf` in the last bit: for about one argument in six for the
sine and the cosine, and one in twenty for the logarithm. Two of the
printed hashes changed with `sinf`. So this file transcribes
numpy's own kernels:

- `sin32` and `cos32` follow `simd_sincos_f32` in
  `numpy/_core/src/umath/loops_trigonometric.dispatch.cpp`: a Cody-Waite
  reduction by pi/2 and two polynomials, all in fused multiply-adds, and
  the C library above 117435.992 (sine) or 71476.0625 (cosine). The
  installed build also fuses the multiply by 2/pi with the add of the
  rounding constant 0x1.8p+23. With the fused form, all 244,000 sines and
  cosines of 122,000 sampled arguments agree with numpy. With two separate
  roundings, two cosines differ.
- `log32` follows the AVX-512 `simd_log_FLOAT` in
  `loops_exponent_log.dispatch.c.src`: a ratio of two polynomials of
  degree five. It agrees with numpy on 100,000 sampled arguments.
- `pow32` follows the exact paths in `loops_umath_fp.dispatch.c.src` for an
  exponent of -1, 0, 0.5, 1 or 2. numpy computes other exponents with
  Intel's SVML `__svml_powf16`, which this file does not transcribe. It
  calls the C library's `powf`. The two differ for about one base in five,
  but they agree on the one such call here, `0.5 ** 10.8649` in
  `specular_dominant`.

Each check compares the bits of numpy 2.5.3's results on this machine.
"""

from std.ffi import external_call
from std.math import floor, fma, sqrt
from std.memory import bitcast

from tools._float32 import mul, round32
from tools._python_float import python_repr
from tools._python_math import power

comptime PLASTIC: Float64 = 1.32471795724474602596
"""The plastic number, which `RNoise.js` names `P`."""
comptime TWO_PI: Float64 = 6.283185307179586
"""Two pi, as Python's `2 * math.pi` gives it."""
comptime PI: Float64 = 3.141592653589793
"""Pi, as Python's `math.pi` gives it."""


def F(x: Float64) -> Float32:
    """Round a double to Float32, as `np.float32(x)` does.

    Args:
        x: The double.

    Returns:
        The nearest Float32.
    """
    return round32(x)


# --- transcendentals ----------------------------------------------------------


def _sincos(x: Float32, cosine: Bool) -> Float32:
    """Return numpy's float32 sine or cosine, from its SIMD kernel.

    numpy reduces x by pi/2 with Cody and Waite's method, in fused
    multiply-adds, and evaluates a polynomial for the sine or the cosine of
    the remainder. Large arguments go to the C library.

    Args:
        x: An angle in radians.
        cosine: True for the cosine, False for the sine.

    Returns:
        The sine or the cosine.
    """
    var limit = F(71476.0625) if cosine else F(117435.992)
    if not abs(x) <= limit:
        if cosine:
            return external_call["cosf", Float32](x)
        return external_call["sinf", Float32](x)
    # 0x1.45f306p-1, 2/pi.
    # 0x1.8p+23 rounds the quadrant to the nearest integer. GCC fuses the
    # kernel's multiply and its first add into one rounding.
    var quadrant = fma(x, F(0.6366197466850281), F(12582912.0))
    quadrant = quadrant - F(12582912.0)
    # -0x1.921fb0p+00, -0x1.5110b4p-22 and -0x1.846988p-48: -pi/2 in parts.
    var r = fma(quadrant, F(-1.570796012878418), x)
    r = fma(quadrant, F(-3.1391647326017846e-07), r)
    r = fma(quadrant, F(-5.390302529957765e-15), r)
    var r2 = mul(r, r)
    # 0x1.98e616p-16, -0x1.6c06dcp-10, 0x1.55553cp-05, -0.5 and 1.
    var c = fma(F(2.4372266125283204e-05), r2, F(-0.001388652017340064))
    c = fma(c, r2, F(0.04166661947965622))
    c = fma(c, r2, F(-0.5))
    c = fma(c, r2, F(1.0))
    # 0x1.7d3bbcp-19, -0x1.a06bbap-13, 0x1.11119ap-07 and -0x1.555556p-03.
    var s = fma(F(2.8404097065504175e-06), r2, F(-0.00019856491417158395))
    s = fma(s, r2, F(0.008333397097885609))
    s = fma(s, r2, F(-0.1666666716337204))
    s = fma(s, r2, Float32(0))
    s = fma(s, r, r)
    var turns = Int(quadrant) + (1 if cosine else 0)
    var result = s if turns & 1 == 0 else c
    if turns & 2 == 2:
        result = Float32(0) - result
    return result


def sin32(x: Float32) -> Float32:
    """Return numpy's float32 sine.

    Args:
        x: An angle in radians.

    Returns:
        The sine.
    """
    return _sincos(x, False)


def cos32(x: Float32) -> Float32:
    """Return numpy's float32 cosine.

    Args:
        x: An angle in radians.

    Returns:
        The cosine.
    """
    return _sincos(x, True)


def log32(x: Float32) -> Float32:
    """Return numpy's float32 natural logarithm, from its AVX-512 kernel.

    numpy splits x into a mantissa in [sqrt(1/2), sqrt(2)) and an exponent,
    and evaluates a ratio of two polynomials in fused multiply-adds.

    Args:
        x: A positive, finite, normal number.

    Returns:
        The logarithm.
    """
    var bits = bitcast[DType.uint32](x)
    # getexp(x) + 1, and getmant(x) in [0.5, 1).
    var exponent = Float32(Int((bits >> 23) & 0xFF) - 126)
    var m = bitcast[DType.float32]((bits & 0x807FFFFF) | (UInt32(126) << 23))
    if m <= F(0.707106781186547524400844362104849039):
        m = m + m
        exponent = exponent - 1
    m = m - 1
    var num = fma(
        F(2.589979117907922693523e-02), m, F(3.808837741388407920751e-01)
    )
    num = fma(num, m, F(1.480000633576506585156e00))
    num = fma(num, m, F(2.112677543073053063722e00))
    num = fma(num, m, F(9.999999999999998702752e-01))
    num = fma(num, m, Float32(0))
    var den = fma(
        F(5.875095403124574342950e-03), m, F(1.546476374983906719538e-01)
    )
    den = fma(den, m, F(9.864942958519418960339e-01))
    den = fma(den, m, F(2.453006071784736363091e00))
    den = fma(den, m, F(2.612677543073109236779e00))
    den = fma(den, m, F(1.0))
    return fma(exponent, F(0.693147180559945309417232121458176568), num / den)


def pow32(x: Float32, y: Float32) -> Float32:
    """Return numpy's float32 power of two scalars.

    numpy's power loop has exact paths for a scalar exponent of -1, 0,
    0.5, 1 and 2. Other exponents go to SVML's `__svml_powf16`; this
    function calls the C library's `powf` for them instead.

    Args:
        x: The base.
        y: The exponent.

    Returns:
        The base to the power of the exponent.
    """
    if y == -1:
        # The C loop divides in double and stores a float.
        return round32(1.0 / Float64(x))
    if y == 0:
        return 1
    if y == 0.5:
        return sqrt(x)
    if y == 1:
        return x
    if y == 2:
        return mul(x, x)
    return external_call["powf", Float32](x, y)


# --- vectors ------------------------------------------------------------------


def add(a: List[Float32], b: List[Float32]) -> List[Float32]:
    """Return the sum of two vectors, each component rounded.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The sum.
    """
    var out = List[Float32]()
    for k in range(len(a)):
        out.append(a[k] + b[k])
    return out^


def sub(a: List[Float32], b: List[Float32]) -> List[Float32]:
    """Return the difference of two vectors, each component rounded.

    Args:
        a: The first vector.
        b: The vector to subtract.

    Returns:
        The difference.
    """
    var out = List[Float32]()
    for k in range(len(a)):
        out.append(a[k] - b[k])
    return out^


def vmul(a: List[Float32], b: List[Float32]) -> List[Float32]:
    """Return the product of two vectors, component by component.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The product.
    """
    var out = List[Float32]()
    for k in range(len(a)):
        out.append(mul(a[k], b[k]))
    return out^


def adds(a: List[Float32], s: Float32) -> List[Float32]:
    """Return a vector plus a scalar.

    Args:
        a: The vector.
        s: The scalar.

    Returns:
        The sum.
    """
    var out = List[Float32]()
    for value in a:
        out.append(value + s)
    return out^


def subs(a: List[Float32], s: Float32) -> List[Float32]:
    """Return a vector minus a scalar.

    Args:
        a: The vector.
        s: The scalar.

    Returns:
        The difference.
    """
    var out = List[Float32]()
    for value in a:
        out.append(value - s)
    return out^


def rsub(s: Float32, a: List[Float32]) -> List[Float32]:
    """Return a scalar minus a vector.

    Args:
        s: The scalar.
        a: The vector.

    Returns:
        The difference.
    """
    var out = List[Float32]()
    for value in a:
        out.append(s - value)
    return out^


def muls(a: List[Float32], s: Float32) -> List[Float32]:
    """Return a vector times a scalar.

    Args:
        a: The vector.
        s: The scalar.

    Returns:
        The product.
    """
    var out = List[Float32]()
    for value in a:
        out.append(mul(value, s))
    return out^


def divs(a: List[Float32], s: Float32) -> List[Float32]:
    """Return a vector divided by a scalar.

    Args:
        a: The vector.
        s: The divisor.

    Returns:
        The quotient.
    """
    var out = List[Float32]()
    for value in a:
        out.append(value / s)
    return out^


def floorv(a: List[Float32]) -> List[Float32]:
    """Return the floor of each component.

    Args:
        a: The vector.

    Returns:
        The floors.
    """
    var out = List[Float32]()
    for value in a:
        out.append(floor(value))
    return out^


def absv(a: List[Float32]) -> List[Float32]:
    """Return the absolute value of each component.

    Args:
        a: The vector.

    Returns:
        The absolute values.
    """
    var out = List[Float32]()
    for value in a:
        out.append(abs(value))
    return out^


def sinv(a: List[Float32]) -> List[Float32]:
    """Return the sine of each component.

    Args:
        a: The angles in radians.

    Returns:
        The sines.
    """
    var out = List[Float32]()
    for value in a:
        out.append(sin32(value))
    return out^


def fract(x: Float32) -> Float32:
    """Return `x - floor(x)`.

    Args:
        x: The value.

    Returns:
        The fractional part.
    """
    return x - floor(x)


def fractv(a: List[Float32]) -> List[Float32]:
    """Return the fractional part of each component.

    Args:
        a: The vector.

    Returns:
        The fractional parts.
    """
    var out = List[Float32]()
    for value in a:
        out.append(fract(value))
    return out^


def mod(x: Float32, y: Float32) -> Float32:
    """Return GLSL's `mod`: `x - y * floor(x / y)`, each step rounded.

    Args:
        x: The dividend.
        y: The divisor.

    Returns:
        The remainder.
    """
    return x - mul(y, floor(x / y))


def modv(a: List[Float32], y: Float32) -> List[Float32]:
    """Return GLSL's `mod` of each component.

    Args:
        a: The dividends.
        y: The divisor.

    Returns:
        The remainders.
    """
    var out = List[Float32]()
    for value in a:
        out.append(mod(value, y))
    return out^


def dot(a: List[Float32], b: List[Float32]) -> Float32:
    """Return a dot product summed from the first component, as the port
    sums it.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The dot product.
    """
    var total = mul(a[0], b[0])
    for k in range(1, len(a)):
        total = total + mul(a[k], b[k])
    return total


def splat(s: Float32, n: Int) -> List[Float32]:
    """Return a vector of n copies of a scalar.

    Args:
        s: The scalar.
        n: The length.

    Returns:
        The vector.
    """
    var out = List[Float32]()
    for _ in range(n):
        out.append(s)
    return out^


def vec32(values: List[Float64]) -> List[Float32]:
    """Round each double to Float32, as `np.array(values, dtype=f)` does.

    Args:
        values: The doubles.

    Returns:
        The Float32 vector.
    """
    var out = List[Float32]()
    for value in values:
        out.append(F(value))
    return out^


def py_max(a: Float32, b: Float32) -> Float32:
    """Return Python's `max(a, b)`: `a` unless `b` is greater.

    Args:
        a: The first value.
        b: The second value.

    Returns:
        The larger value.
    """
    return b if b > a else a


def py_min(a: Float32, b: Float32) -> Float32:
    """Return Python's `min(a, b)`: `a` unless `b` is smaller.

    Args:
        a: The first value.
        b: The second value.

    Returns:
        The smaller value.
    """
    return b if b < a else a


def normalize(v: List[Float32]) -> List[Float32]:
    """Return a vector divided by its length, or the vector if its length
    is zero.

    Args:
        v: The vector.

    Returns:
        The unit vector.
    """
    var n = sqrt(dot(v, v))
    if n != 0:
        return divs(v, n)
    return v.copy()


def cross(a: List[Float32], b: List[Float32]) -> List[Float32]:
    """Return the cross product, as `np.cross` rounds it.

    Args:
        a: The first vector.
        b: The second vector.

    Returns:
        The cross product.
    """
    return [
        mul(a[1], b[2]) - mul(a[2], b[1]),
        mul(a[2], b[0]) - mul(a[0], b[2]),
        mul(a[0], b[1]) - mul(a[1], b[0]),
    ]


# --- hash ---------------------------------------------------------------------


def pcg_hash(seed: Int) -> Float32:
    """Return `Hash.js`'s PCG hash of an integer, in [0, 1).

    Args:
        seed: A non-negative integer.

    Returns:
        The hash.
    """
    var mask = UInt64(0xFFFFFFFF)
    var state = (UInt64(seed) * 747796405 + 2891336453) & mask
    var word = (((state >> ((state >> 28) + 4)) ^ state) * 277803737) & mask
    var result = ((word >> 22) ^ word) & mask
    return mul(F(Float64(result)), F(1.0 / 4294967296.0))


# --- bits ---------------------------------------------------------------------


def float_bits(x: Float64) -> UInt32:
    """Return the bits of a double rounded to Float32.

    Args:
        x: The double.

    Returns:
        The Float32 bits.
    """
    return bitcast[DType.uint32](F(x))


def half_bits(value: Float64) -> Int:
    """Round a double to the nearest half, ties to even, as numpy's float16
    cast does. A value too large for a half gives infinity.

    Args:
        value: The value.

    Returns:
        The half's bits.
    """
    var bits = bitcast[DType.uint64](value)
    var sign = Int(bits >> 63) << 15
    var field = Int((bits >> 52) & 0x7FF)
    var fraction = Int(bits & ((UInt64(1) << 52) - 1))
    if field == 0x7FF:
        return sign | (0x7C00 if fraction == 0 else 0x7E00)
    if field == 0 and fraction == 0:
        return sign
    var significand = fraction | (1 << 52) if field else fraction
    var scale = (field if field else 1) - 1075
    var length = 0
    while (significand >> length) > 0:
        length += 1
    var exponent = length - 1 + scale
    if exponent > 15:
        return sign | 0x7C00
    var unit = max(exponent, -14) - 10
    var shift = unit - scale
    var q: Int
    if shift <= 0:
        q = significand << -shift
    elif shift >= 62:
        q = 0
    else:
        q = significand >> shift
        var rest = significand & ((1 << shift) - 1)
        var half = 1 << (shift - 1)
        if rest > half or (rest == half and q & 1 == 1):
            q += 1
    if q >= 2048:
        q >>= 1
        unit += 1
    if q < 1024:
        return sign | q
    var stored = unit + 25
    if stored >= 31:
        return sign | 0x7C00
    return sign | (stored << 10) | (q - 1024)


# --- triNoise3D ---------------------------------------------------------------


def tri(x: Float32) -> Float32:
    """Return `TriNoise3D.js`'s `tri`: `abs(fract(x) - 0.5)`.

    Args:
        x: The value.

    Returns:
        The triangle wave.
    """
    return abs(fract(x) - F(0.5))


def tri3(p: List[Float32]) -> List[Float32]:
    """Return `TriNoise3D.js`'s `tri3`.

    Args:
        p: The point.

    Returns:
        The three triangle waves.
    """
    return [
        tri(p[2] + tri(p[1])),
        tri(p[2] + tri(p[0])),
        tri(p[1] + tri(p[0])),
    ]


def tri_noise_3d(
    position: List[Float64], speed: Float64, time: Float64
) -> Float32:
    """Return `TriNoise3D.js`'s `triNoise3D`.

    Args:
        position: The point.
        speed: The speed.
        time: The time.

    Returns:
        The noise.
    """
    var p = vec32(position)
    var z = F(1.4)
    var rz = Float32(0)
    var bp = p.copy()
    var drift = mul(F(time), mul(F(0.1), F(speed)))
    for _ in range(4):
        var dg = tri3(muls(bp, 2))
        p = add(p, adds(dg, drift))
        bp = muls(bp, F(1.8))
        z = mul(z, F(1.5))
        p = muls(p, F(1.2))
        var t = tri(p[2] + tri(p[0] + tri(p[1])))
        rz = rz + t / z
        bp = adds(bp, F(0.14))
    return rz


# --- simplex and curl noise ---------------------------------------------------


def permute(x: List[Float32]) -> List[Float32]:
    """Return `curlNoise.js`'s `permute`: `mod(x * x * 34 + x, 289)`.

    Args:
        x: The values.

    Returns:
        The permuted values.
    """
    return modv(add(muls(vmul(x, x), 34), x), 289)


def snoise(v: List[Float32]) -> Float32:
    """Return `curlNoise.js`'s 3D simplex noise.

    Args:
        v: The point.

    Returns:
        The noise, near [0, 1].
    """
    var c0 = Float32(1) / Float32(6)
    var c1 = Float32(1) / Float32(3)
    var i = floorv(adds(v, dot(v, splat(c1, 3))))
    var x0 = adds(sub(v, i), dot(i, splat(c0, 3)))
    var g = List[Float32]()
    for k in range(3):
        g.append(Float32(1) if x0[k] >= x0[(k + 1) % 3] else Float32(0))
    var l = rsub(1, g)
    var i1 = List[Float32]()
    var i2 = List[Float32]()
    for k in range(3):
        var other = l[(k + 2) % 3]
        i1.append(min(g[k], other))
        i2.append(max(g[k], other))
    var x1 = adds(sub(x0, i1), c0)
    var x2 = adds(sub(x0, i2), c1)
    var x3 = subs(x0, F(0.5))
    i = modv(i, 289)
    var p = permute(adds([0, i1[2], i2[2], 1], i[2]))
    p = permute(add(adds(p, i[1]), [0, i1[1], i2[1], 1]))
    p = permute(add(adds(p, i[0]), [0, i1[0], i2[0], 1]))
    var ns = sub(muls([2, 0.5, 1], F(0.142857142857)), [0, 1, 0])
    var j = sub(p, muls(floorv(muls(muls(p, ns[2]), ns[2])), 49))
    var x_ = floorv(muls(j, ns[2]))
    var x = adds(muls(x_, ns[0]), ns[1])
    var y = adds(muls(floorv(sub(j, muls(x_, 7))), ns[0]), ns[1])
    var h = sub(rsub(1, absv(x)), absv(y))
    var b0: List[Float32] = [x[0], x[1], y[0], y[1]]
    var b1: List[Float32] = [x[2], x[3], y[2], y[3]]
    var sh = List[Float32]()
    for k in range(4):
        var stepped = Float32(1) if Float32(0) >= h[k] else Float32(0)
        sh.append(-stepped)
    var f0 = adds(muls(floorv(b0), 2), 1)
    var f1 = adds(muls(floorv(b1), 2), 1)
    var order: List[Int] = [0, 2, 1, 3]
    var a0 = List[Float32]()
    var a1 = List[Float32]()
    for k in range(4):
        var q = order[k]
        a0.append(b0[q] + mul(f0[q], sh[k // 2]))
        a1.append(b1[q] + mul(f1[q], sh[2 + k // 2]))
    var ps: List[List[Float32]] = [
        [a0[0], a0[1], h[0]],
        [a0[2], a0[3], h[1]],
        [a1[0], a1[1], h[2]],
        [a1[2], a1[3], h[3]],
    ]
    var xs: List[List[Float32]] = [x0.copy(), x1.copy(), x2.copy(), x3.copy()]
    var norms = List[Float32]()
    for k in range(4):
        norms.append(Float32(1) / sqrt(dot(ps[k], ps[k])))
    for k in range(4):
        ps[k] = muls(ps[k], norms[k])
    var m = List[Float32]()
    var grades = List[Float32]()
    for k in range(4):
        m.append(max(F(0.6) - dot(xs[k], xs[k]), Float32(0)))
    for k in range(4):
        grades.append(dot(ps[k], xs[k]))
    return F(0.5) + mul(12, dot(vmul(vmul(m, m), m), grades))


def snoise_vec3(p: List[Float64]) -> List[Float32]:
    """Return `curlNoise.js`'s `snoiseVec3` of a point given in doubles.

    Args:
        p: The point.

    Returns:
        Three noises.
    """
    return snoise_vec3_32(vec32(p))


def snoise_vec3_32(x: List[Float32]) -> List[Float32]:
    """Return `curlNoise.js`'s `snoiseVec3`.

    Args:
        x: The point.

    Returns:
        Three noises.
    """
    var first = snoise(subs(muls(x, 2), 1))
    var second = (
        mul(
            snoise([x[1] - F(19.1), x[2] + F(33.4), x[0] + F(47.2)]),
            2,
        )
        - 1
    )
    var third = snoise(
        subs(muls([x[2] + F(74.2), x[0] - F(124.5), x[1] + F(99.4)], 2), 1)
    )
    return [first, second, third]


def curl_noise(point: List[Float64]) -> List[Float32]:
    """Return `curlNoise.js`'s `curlNoise`.

    Args:
        point: The point.

    Returns:
        The curl.
    """
    var p = vec32(point)
    var e = F(0.1)
    var dx: List[Float32] = [e, 0, 0]
    var dy: List[Float32] = [0, e, 0]
    var dz: List[Float32] = [0, 0, e]
    var p_x0 = snoise_vec3_32(sub(p, dx))
    var p_x1 = snoise_vec3_32(add(p, dx))
    var p_y0 = snoise_vec3_32(sub(p, dy))
    var p_y1 = snoise_vec3_32(add(p, dy))
    var p_z0 = snoise_vec3_32(sub(p, dz))
    var p_z1 = snoise_vec3_32(add(p, dz))
    var x = p_y1[2] - p_y0[2] - p_z1[1] + p_z0[1]
    var y = p_z1[0] - p_z0[0] - p_x1[2] + p_x0[2]
    var z = p_x1[1] - p_x0[1] - p_y1[0] + p_y0[0]
    var divisor = Float32(1) / mul(2, e)
    return muls([x, y, z], divisor)


# --- Voronoi ------------------------------------------------------------------


def hash2d(p: List[Float32]) -> List[Float32]:
    """Return `voronoiNoise.js`'s 2D cell hash.

    Args:
        p: The cell.

    Returns:
        Two values in [0, 1).
    """
    var d: List[Float32] = [
        dot(p, vec32([127.1, 311.7])),
        dot(p, vec32([269.5, 183.3])),
    ]
    return fractv(muls(sinv(d), F(18.5453)))


def hash3d(p: List[Float32]) -> List[Float32]:
    """Return `voronoiNoise.js`'s 3D cell hash.

    Args:
        p: The cell.

    Returns:
        Three values in [0, 1).
    """
    var d: List[Float32] = [
        dot(p, vec32([127.1, 311.7, 74.7])),
        dot(p, vec32([269.5, 183.3, 246.1])),
        dot(p, vec32([113.5, 271.9, 124.6])),
    ]
    return fractv(muls(sinv(d), F(18.5453)))


def voronoi(point: List[Float64], time: Float64) -> Float32:
    """Return `voronoiNoise.js`'s distance to the nearest cell point, in
    two or three dimensions.

    Args:
        point: The point, of two or three components.
        time: The time.

    Returns:
        The squared distance.
    """
    var p = vec32(point)
    var dims = len(p)
    var n = floorv(p)
    var fr = fractv(p)
    var nearest = F(8)
    var count = 1
    for _ in range(dims):
        count *= 3
    for index in range(count):
        # itertools.product: the last index varies fastest.
        var g = List[Float32]()
        var rest = index
        var divisor = count
        for _ in range(dims):
            divisor //= 3
            g.append(Float32((rest // divisor) - 1))
            rest %= divisor
        var cell = add(n, g)
        var o = hash2d(cell) if dims == 2 else hash3d(cell)
        var wave = sinv(adds(muls(o, F(TWO_PI)), F(time)))
        var r = add(sub(g, fr), adds(muls(wave, F(0.5)), F(0.5)))
        nearest = py_min(nearest, dot(r, r))
    return nearest


# --- RNoise -------------------------------------------------------------------


def analytic_noise(
    uv: List[Float64], sample_index: Int, resolution: List[Int], seed: Int
) -> List[Float32]:
    """Return `RNoise.js`'s analytic noise.

    Args:
        uv: The texture coordinate.
        sample_index: The sample's index.
        resolution: The width and height.
        seed: The seed.

    Returns:
        Four values in [0, 1).
    """
    var index = F(Float64(sample_index + seed))
    var res: List[Float64] = [Float64(resolution[0]), Float64(resolution[1])]
    var pixel = floorv(vmul(vec32(uv), vec32(res)))
    var offset = floorv(
        muls(
            fractv([mul(index, F(0.7548776662)), mul(index, F(0.5698402910))]),
            32,
        )
    )
    var c = modv(add(pixel, offset), 32)
    var p2 = power(PLASTIC, 2.0)
    var p3 = power(PLASTIC, 3.0)
    var t = (
        mul(c[0], F(1.0 / PLASTIC)) + mul(c[1], F(1.0 / p2)) + F(Float64(seed))
    )
    return [
        fract(mul(mul(t, F(PLASTIC)), F(1.0 / PLASTIC))),
        fract(mul(mul(t, F(PLASTIC * 2.0)), F(1.0 / p2))),
        fract(mul(mul(t, F(PLASTIC * 3.0)), F(0.4198754210))),
        fract(mul(mul(t, F(PLASTIC * 4.0)), F(1.0 / p3))),
    ]


# --- specular helpers ---------------------------------------------------------


def sample_ggx_vndf(
    v: List[Float32], ax: Float32, ay: Float32, r1: Float32, r2: Float32
) -> List[Float32]:
    """Return `SpecularHelpers.js`'s visible-normal GGX sample.

    Args:
        v: The view direction in tangent space.
        ax: The roughness along x.
        ay: The roughness along y.
        r1: The first random number.
        r2: The second random number.

    Returns:
        The half vector in tangent space.
    """
    var wi = normalize([mul(ax, v[0]), mul(ay, v[1]), v[2]])
    var a = py_min(ax, ay)
    var s = 1 + sqrt(mul(v[0], v[0]) + mul(v[1], v[1]))
    var a2 = mul(a, a)
    var s2 = mul(s, s)
    var k = mul(1 - a2, s2) / (s2 + mul(mul(a2, v[2]), v[2]))
    var b = mul(wi[2], k)
    var phi = mul(F(TWO_PI), r1)
    var z = mul(1 - r2, 1 + b) - b
    var sin_theta = sqrt(py_max(0, 1 - mul(z, z)))
    var c: List[Float32] = [
        mul(sin_theta, cos32(phi)),
        mul(sin_theta, sin32(phi)),
        z,
    ]
    var wm = add(c, wi)
    return normalize([mul(ax, wm[0]), mul(ay, wm[1]), py_max(0, wm[2])])


def d_gtr(r: Float32, noh: Float32, k: Float32) -> Float32:
    """Return `SpecularHelpers.js`'s generalized Trowbridge-Reitz `D`.

    Args:
        r: The roughness.
        noh: The cosine between the normal and the half vector.
        k: The exponent.

    Returns:
        The distribution.
    """
    var a2 = mul(r, r)
    var base = mul(mul(noh, noh), a2 - 1) + 1
    return a2 / mul(F(PI), pow32(base, k))


def smith_g(ndx: Float32, alpha: Float32) -> Float32:
    """Return `SpecularHelpers.js`'s Smith `G1`.

    Args:
        ndx: The cosine between the normal and the direction.
        alpha: The roughness squared.

    Returns:
        The masking term.
    """
    var a2 = mul(alpha, alpha)
    return mul(2, ndx) / (ndx + sqrt(a2 + mul(mul(1 - a2, ndx), ndx)))


def ggx_vndf_pdf(noh: Float32, nov: Float32, r: Float32) -> Float32:
    """Return `SpecularHelpers.js`'s visible-normal GGX density.

    Args:
        noh: The cosine between the normal and the half vector.
        nov: The cosine between the normal and the view direction.
        r: The roughness.

    Returns:
        The density.
    """
    var d = d_gtr(r, noh, 2)
    var a2 = mul(r, r)
    var sin_v2 = py_max(0, 1 - mul(nov, nov))
    var s = 1 + sqrt(sin_v2)
    var s2 = mul(s, s)
    var k = mul(1 - a2, s2) / (s2 + mul(mul(a2, nov), nov))
    var t = sqrt(mul(a2, sin_v2) + mul(nov, nov))
    return d / py_max(F(1e-6), mul(2, mul(k, nov) + t))


def specular_dominant(nov: Float32, r: Float32) -> Float32:
    """Return `SpecularHelpers.js`'s specular dominant factor.

    Args:
        nov: The cosine between the normal and the view direction.
        r: The roughness.

    Returns:
        The factor, in [0, 1].
    """
    var a = mul(F(0.298475), log32(F(39.4115) - mul(F(39.0029), r)))
    var value = mul(pow32(1 - nov, F(10.8649)), 1 - a) + a
    return py_min(py_max(value, 0), 1)


@fieldwise_init
struct GgxSample(Copyable, Movable):
    """The outputs of `ggx_reflection_sample`."""

    var l: List[Float32]
    """The reflected direction."""
    var weight: List[Float32]
    """The sample's weight."""
    var pdf: Float32
    """The sample's density."""
    var nov: Float32
    """The cosine between the normal and the view direction."""
    var a: Float32
    """The clamped roughness squared."""
    var f0: List[Float32]
    """The reflectance at normal incidence."""


def ggx_reflection_sample(
    normal: List[Float64],
    view: List[Float64],
    roughness: Float64,
    metalness: Float64,
    albedo: List[Float64],
    xi: List[Float64],
) -> GgxSample:
    """Return `SpecularHelpers.js`'s GGX reflection sample.

    Args:
        normal: The surface normal.
        view: The view direction.
        roughness: The roughness.
        metalness: The metalness.
        albedo: The base color.
        xi: Two random numbers.

    Returns:
        The direction, weight, density and inputs that the test checks.
    """
    var n = vec32(normal)
    var v = vec32(view)
    var base = vec32(albedo)
    var a = py_max(mul(F(roughness), F(roughness)), F(0.001))
    var t_axis = normalize(cross([0, 0, 1], n))
    if sqrt(dot(t_axis, t_axis)) < 1e-3:
        t_axis = normalize(cross([0, 1, 0], n))
    var b_axis = normalize(cross(n, t_axis))
    var vl: List[Float32] = [dot(t_axis, v), dot(b_axis, v), dot(n, v)]
    var hl = sample_ggx_vndf(vl, a, a, F(xi[0]), F(xi[1]))
    if hl[2] < 0:
        for k in range(3):
            hl[k] = -hl[k]
    var h = normalize(
        add(add(muls(t_axis, hl[0]), muls(b_axis, hl[1])), muls(n, hl[2]))
    )
    var neg_v = List[Float32]()
    for value in v:
        neg_v.append(-value)
    var l = normalize(sub(neg_v, muls(h, mul(2, dot(h, neg_v)))))
    var half = normalize(add(v, l))
    var nov = py_max(0, dot(n, v))
    var nol = py_max(0, dot(n, l))
    var noh = py_max(0, dot(n, half))
    var voh = py_max(0, dot(v, half))
    var metal = F(metalness)
    var f0 = add(muls(splat(F(0.04), 3), 1 - metal), muls(base, metal))
    var om = 1 - voh
    var om5 = mul(mul(mul(mul(om, om), om), om), om)
    var fres = add(f0, muls(rsub(1, f0), om5))
    var pdf = ggx_vndf_pdf(noh, nov, a)
    var a2 = mul(a, a)
    var sin_v2 = py_max(1 - mul(nov, nov), 0)
    var s = 1 + sqrt(sin_v2)
    var s2 = mul(s, s)
    var k = mul(1 - a2, s2) / (s2 + mul(mul(a2, nov), nov))
    var t = sqrt(mul(a2, sin_v2) + mul(nov, nov))
    var g2 = mul(smith_g(nov, a), smith_g(nol, a))
    var weight = divs(
        muls(muls(fres, g2), mul(k, nov) + t), py_max(mul(2, nov), F(1e-4))
    )
    return GgxSample(l^, weight^, pdf, nov, a, f0^)


# --- report -------------------------------------------------------------------


def hex_text(value: UInt32) -> String:
    """Return Python's `hex` of a non-negative integer.

    Args:
        value: The integer.

    Returns:
        The lowercase digits after `0x`, without padding.
    """
    var digits = "0123456789abcdef"
    if value == 0:
        return "0x0"
    var out = String()
    var rest = value
    while rest > 0:
        out = String(digits[byte=Int(rest & 15)]) + out
        rest >>= 4
    return "0x" + out


def tuple_text(values: List[Float64]) raises -> String:
    """Return a tuple of floats as Python prints it.

    Args:
        values: The floats.

    Returns:
        The text, such as `(0.3, 0.7)`.

    Raises:
        Error: Never; float text cannot fail for finite values.
    """
    var words = List[String]()
    for value in values:
        words.append(python_repr(value))
    return "(" + ", ".join(words) + ")"


def repr32(value: Float32) raises -> String:
    """Return `repr(float(value))` for a Float32.

    Args:
        value: The value.

    Returns:
        The shortest text of the widened double.

    Raises:
        Error: Never; float text cannot fail for finite values.
    """
    return python_repr(Float64(value))


def quoted_list(values: List[Float32]) raises -> String:
    """Return Python's print of `[repr(float(c)) for c in values]`.

    Args:
        values: The values.

    Returns:
        The text, such as `['0.5', '0.25']`.

    Raises:
        Error: Never; float text cannot fail for finite values.
    """
    var words = List[String]()
    for value in values:
        words.append("'" + repr32(value) + "'")
    return "[" + ", ".join(words) + "]"


def report() raises -> String:
    """Return the values the tests check, one line each.

    Returns:
        The lines, each ended by a newline.

    Raises:
        Error: Never; float text cannot fail for finite values.
    """
    var out = String()
    for seed in [0, 1, 7, 12345, 16777215]:
        out += "hash " + String(seed) + " " + repr32(pcg_hash(seed)) + "\n"
    var floats: List[Float64] = [
        1.0,
        -2.5,
        0.1,
        8.0,
        0.99999994,
        3.0e38,
        1.1754944e-38,
        123456.789,
    ]
    for x in floats:
        var b = float_bits(x)
        out += (
            "bits "
            + python_repr(x)
            + " "
            + hex_text(b)
            + " "
            + String(b & 0xFFFF)
            + " "
            + String(b >> 16)
            + "\n"
        )
    var halves: List[Float64] = [
        1.0,
        -2.0,
        65504.0,
        65519.0,
        65520.0,
        1e-5,
        0.1,
        6.1035156e-05,
        -0.33333334,
        5.9604645e-08,
        2.9802322e-08,
        8.940697e-08,
    ]
    for x in halves:
        out += (
            "half "
            + python_repr(x)
            + " "
            + hex_text(UInt32(half_bits(x)))
            + "\n"
        )
    var tri_points: List[List[Float64]] = [[0.3, 0.7, 1.1], [2.5, -1.25, 0.4]]
    var speeds: List[Float64] = [1.0, 0.3]
    var times: List[Float64] = [0.5, 3.0]
    for k in range(2):
        out += (
            "triNoise3D "
            + tuple_text(tri_points[k])
            + " "
            + python_repr(speeds[k])
            + " "
            + python_repr(times[k])
            + " "
            + repr32(tri_noise_3d(tri_points[k], speeds[k], times[k]))
            + "\n"
        )
    var points: List[List[Float64]] = [
        [0.3, 0.7, 1.1],
        [2.5, -1.25, 0.4],
        [-3.7, 5.2, 0.05],
    ]
    for p in points:
        var text = tuple_text(p)
        out += "snoise " + text + " " + repr32(snoise(vec32(p))) + "\n"
        out += "snoiseVec3 " + text + " " + quoted_list(snoise_vec3(p)) + "\n"
        out += "curl " + text + " " + quoted_list(curl_noise(p)) + "\n"
    var cell_times: List[Float64] = [0.0, 1.5]
    var flat: List[List[Float64]] = [[0.3, 0.7], [2.5, -1.25]]
    for k in range(2):
        var text = tuple_text(flat[k]) + " " + python_repr(cell_times[k])
        out += (
            "voronoi2d "
            + text
            + " "
            + repr32(voronoi(flat[k], cell_times[k]))
            + "\n"
        )
        out += (
            "hash2d "
            + tuple_text(flat[k])
            + " "
            + quoted_list(hash2d(vec32(flat[k])))
            + "\n"
        )
    var solid: List[List[Float64]] = [[0.3, 0.7, 1.1], [2.5, -1.25, 0.4]]
    for k in range(2):
        var text = tuple_text(solid[k]) + " " + python_repr(cell_times[k])
        out += (
            "voronoi3d "
            + text
            + " "
            + repr32(voronoi(solid[k], cell_times[k]))
            + "\n"
        )
        out += (
            "hash3d "
            + tuple_text(solid[k])
            + " "
            + quoted_list(hash3d(vec32(solid[k])))
            + "\n"
        )
    var uvs: List[List[Float64]] = [[0.25, 0.75], [0.6, 0.1]]
    var indices: List[Int] = [0, 3]
    var sizes: List[List[Int]] = [[64, 32], [800, 600]]
    var seeds: List[Int] = [0, 2]
    for k in range(2):
        out += (
            "rnoise "
            + tuple_text(uvs[k])
            + " "
            + String(indices[k])
            + " ("
            + String(sizes[k][0])
            + ", "
            + String(sizes[k][1])
            + ") "
            + String(seeds[k])
            + " "
            + quoted_list(
                analytic_noise(uvs[k], indices[k], sizes[k], seeds[k])
            )
            + "\n"
        )
    var vndf = sample_ggx_vndf(
        vec32([0.3, 0.2, 0.9327379]), F(0.4), F(0.4), F(0.25), F(0.6)
    )
    out += "vndf " + quoted_list(vndf) + "\n"
    out += "d_gtr " + repr32(d_gtr(F(0.5), F(0.8), 2)) + "\n"
    out += "smith_g " + repr32(smith_g(F(0.7), F(0.3))) + "\n"
    out += "pdf " + repr32(ggx_vndf_pdf(F(0.9), F(0.6), F(0.4))) + "\n"
    out += "dominant " + repr32(specular_dominant(F(0.5), F(0.3))) + "\n"
    var sample = ggx_reflection_sample(
        [0, 0.6, 0.8], [0.28, 0.0, 0.96], 0.5, 0.3, [0.9, 0.5, 0.2], [0.3, 0.7]
    )
    out += "ggx L " + quoted_list(sample.l) + "\n"
    out += "ggx w " + quoted_list(sample.weight) + "\n"
    out += (
        "ggx pdf nov a "
        + repr32(sample.pdf)
        + " "
        + repr32(sample.nov)
        + " "
        + repr32(sample.a)
        + "\n"
    )
    out += "ggx f0 " + quoted_list(sample.f0) + "\n"
    return out^


def main() raises:
    print(report(), end="")
