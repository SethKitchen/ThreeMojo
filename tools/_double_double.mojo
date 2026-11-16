# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Double-double arithmetic: about 32 significant digits from two doubles.

A reference tool must have more digits than the library it checks, so
that its own rounding stays far below the tolerance of the test. `DD`
holds a number as the sum `hi + lo` of two doubles, with `|lo|` at most
half a unit in the last place of `hi`. The algorithms are those of Dekker
(1971) and of the QD library of Hida, Li and Bailey (2001).

- `+`, `-`, `*` and `/` take two `DD` numbers, or a `DD` and a `Float64`.
  Each result is good to about 1e-32 of its size.
- `dd_sqrt`, `dd_exp`, `dd_log` and `dd_pow` give the root, `e^x`, `ln x`
  and `x^y` to about 1e-31.
- `dd_parse` reads a decimal number, such as a published constant.
- `dd_solve` solves a small linear system by Gauss-Jordan elimination with
  partial pivots. `dd_inverse` inverts a small matrix.
- `dd_normal_quantile(p)` gives the normal quantile, by Newton steps on
  the Taylor series of erf.

`dd_ln2()` and `dd_pi()` are the constants of QD. The tool tests check each
against its published decimal digits.

Each exact product goes through `fma`, so a default build, which fuses
`a * b + c`, gives the same digits as a build with `contract=off`.
"""

from std.math import floor, fma, inf, ldexp, log, sqrt


comptime _LN2_HI = 6.931471805599452862e-01
comptime _LN2_LO = 2.319046813846299558e-17
comptime _PI_HI = 3.141592653589793116e00
comptime _PI_LO = 1.224646799147353207e-16


def _two_sum(a: Float64, b: Float64) -> Tuple[Float64, Float64]:
    """Return `a + b` rounded, and its exact rounding error (Knuth)."""
    var s = a + b
    var bb = s - a
    var e = (a - (s - bb)) + (b - bb)
    return (s, e)


def _quick_two_sum(a: Float64, b: Float64) -> Tuple[Float64, Float64]:
    """Return `a + b` rounded and its error, for `|a| >= |b|` (Dekker)."""
    var s = a + b
    var e = b - (s - a)
    return (s, e)


def _two_prod(a: Float64, b: Float64) -> Tuple[Float64, Float64]:
    """Return `a b` rounded, and its exact rounding error, by `fma`."""
    var p = a * b
    var e = fma(a, b, -p)
    return (p, e)


@fieldwise_init
struct DD(ImplicitlyCopyable):
    """A double-double number: the sum `hi + lo` of two doubles."""

    var hi: Float64
    """The leading double."""
    var lo: Float64
    """The trailing double, at most half an ulp of `hi`."""

    def __add__(self, other: DD) -> DD:
        """Add two numbers.

        Args:
            other: The other number.

        Returns:
            The sum.
        """
        var s = _two_sum(self.hi, other.hi)
        var t = _two_sum(self.lo, other.lo)
        var u = _quick_two_sum(s[0], s[1] + t[0])
        var v = _quick_two_sum(u[0], u[1] + t[1])
        return DD(v[0], v[1])

    def __add__(self, other: Float64) -> DD:
        """Add a double.

        Args:
            other: The double.

        Returns:
            The sum.
        """
        return self + DD(other, 0.0)

    def __radd__(self, other: Float64) -> DD:
        """Add to a double.

        Args:
            other: The double.

        Returns:
            The sum.
        """
        return DD(other, 0.0) + self

    def __neg__(self) -> DD:
        """Return the negative.

        Returns:
            `-x`.
        """
        return DD(-self.hi, -self.lo)

    def __sub__(self, other: DD) -> DD:
        """Subtract a number.

        Args:
            other: The number to take away.

        Returns:
            The difference.
        """
        return self + (-other)

    def __sub__(self, other: Float64) -> DD:
        """Subtract a double.

        Args:
            other: The double to take away.

        Returns:
            The difference.
        """
        return self + DD(-other, 0.0)

    def __rsub__(self, other: Float64) -> DD:
        """Subtract from a double.

        Args:
            other: The double.

        Returns:
            `other - x`.
        """
        return DD(other, 0.0) - self

    def __mul__(self, other: DD) -> DD:
        """Multiply two numbers.

        Args:
            other: The other number.

        Returns:
            The product.
        """
        var p = _two_prod(self.hi, other.hi)
        var e = p[1] + (self.hi * other.lo + self.lo * other.hi)
        var u = _quick_two_sum(p[0], e)
        return DD(u[0], u[1])

    def __mul__(self, other: Float64) -> DD:
        """Multiply by a double.

        Args:
            other: The double.

        Returns:
            The product.
        """
        var p = _two_prod(self.hi, other)
        var u = _quick_two_sum(p[0], p[1] + self.lo * other)
        return DD(u[0], u[1])

    def __rmul__(self, other: Float64) -> DD:
        """Multiply a double.

        Args:
            other: The double.

        Returns:
            The product.
        """
        return self * other

    def __truediv__(self, other: DD) -> DD:
        """Divide by a number, with three quotient digits.

        Args:
            other: The divisor, not 0.

        Returns:
            The quotient.
        """
        var q1 = self.hi / other.hi
        var r = self - other * q1
        var q2 = r.hi / other.hi
        r = r - other * q2
        var q3 = r.hi / other.hi
        var u = _quick_two_sum(q1, q2)
        return DD(u[0], u[1]) + q3

    def __truediv__(self, other: Float64) -> DD:
        """Divide by a double.

        Args:
            other: The divisor, not 0.

        Returns:
            The quotient.
        """
        return self / DD(other, 0.0)

    def __rtruediv__(self, other: Float64) -> DD:
        """Divide a double.

        Args:
            other: The dividend.

        Returns:
            `other / x`.
        """
        return DD(other, 0.0) / self

    def __lt__(self, other: DD) -> Bool:
        """Compare two numbers.

        Args:
            other: The other number.

        Returns:
            True if this number is below the other.
        """
        return self.hi < other.hi or (
            self.hi == other.hi and self.lo < other.lo
        )

    def __gt__(self, other: DD) -> Bool:
        """Compare two numbers.

        Args:
            other: The other number.

        Returns:
            True if this number is above the other.
        """
        return other < self

    def to_float(self) -> Float64:
        """Return the nearest double.

        Returns:
            `hi + lo`, rounded once.
        """
        return self.hi + self.lo


def dd(x: Float64) -> DD:
    """Return a double as a double-double number.

    Args:
        x: The double.

    Returns:
        `x + 0`.
    """
    return DD(x, 0.0)


def dd_abs(a: DD) -> DD:
    """Return the size of a number.

    Args:
        a: The number.

    Returns:
        `|a|`.
    """
    return -a if a.hi < 0.0 else a


def dd_ln2() -> DD:
    """Return the natural logarithm of 2.

    Returns:
        The logarithm, to about 1e-33.
    """
    return DD(_LN2_HI, _LN2_LO)


def dd_pi() -> DD:
    """Return pi.

    Returns:
        The constant, to about 1e-32.
    """
    return DD(_PI_HI, _PI_LO)


def dd_sqrt(a: DD) raises -> DD:
    """Return the square root, by one Newton step from the double root.

    Args:
        a: The number, 0 or more.

    Returns:
        The root.

    Raises:
        Error: If the number is negative.
    """
    if a.hi < 0.0:
        raise Error("A double-double root needs a number of 0 or more")
    if a.hi == 0.0:
        return dd(0.0)
    var x = dd(sqrt(a.hi))
    x = x + (a - x * x) / (x * 2.0)
    return x + (a - x * x) / (x * 2.0)


def _scale(a: DD, exponent: Int) -> DD:
    """Return `a 2^exponent`, exactly while both parts stay normal."""
    return DD(ldexp(a.hi, Int32(exponent)), ldexp(a.lo, Int32(exponent)))


def dd_exp(a: DD) raises -> DD:
    """Return `e^a`.

    The argument is `k ln 2 + r`, with `|r| <= ln 2 / 2`. The Taylor
    series of `e^(r / 1024) - 1` is squared ten times as `2 s + s^2`, which
    keeps the digits of a small `s`, then raised by `2^k`.

    Args:
        a: The power, from -700 to 700.

    Returns:
        `e^a`.

    Raises:
        Error: If the power is outside -700 to 700.
    """
    if not (a.hi >= -700.0 and a.hi <= 700.0):
        raise Error("A double-double exponential needs a power within 700")
    var k = floor(a.hi / _LN2_HI + 0.5)
    var r = _scale(a - dd_ln2() * k, -10)
    var term = r
    var s = r
    for n in range(2, 40):
        term = term * r / Float64(n)
        s = s + term
        if abs(term.hi) <= 1e-36 * abs(s.hi) or term.hi == 0.0:
            break
    for _ in range(10):
        s = s * 2.0 + s * s
    return _scale(s + 1.0, Int(k))


def dd_log(a: DD) raises -> DD:
    """Return `ln a`, by two Newton steps from the double logarithm.

    Each step is `x + a e^-x - 1`, which doubles the digits.

    Args:
        a: The number, above 0.

    Returns:
        `ln a`.

    Raises:
        Error: If the number is not above 0.
    """
    if not (a.hi > 0.0) or a.hi == inf[DType.float64]():
        raise Error("A double-double logarithm needs a finite number above 0")
    var x = dd(log(a.hi))
    for _ in range(2):
        x = x + a * dd_exp(-x) - 1.0
    return x


def dd_pow(a: DD, b: DD) raises -> DD:
    """Return `a^b` as `e^(b ln a)`.

    Args:
        a: The base, above 0.
        b: The power.

    Returns:
        `a^b`.

    Raises:
        Error: If the base is not above 0, or the power `b ln a` is outside
            -700 to 700.
    """
    return dd_exp(b * dd_log(a))


def dd_parse(text: String) raises -> DD:
    """Read a decimal number, such as `-0.6931471805599453094172`.

    Each digit enters as `10 x + d`, so the number is good to about 1e-32
    for up to 50 digits.

    Args:
        text: An optional minus sign, digits, and an optional point with
            more digits.

    Returns:
        The number.

    Raises:
        Error: If the text holds another character, or no digit.
    """
    var value = dd(0.0)
    var after = 0
    var point = False
    var digits = 0
    var negative = False
    var first = True
    for byte in text.as_bytes():
        if first and byte == 45:
            negative = True
        elif byte == 46 and not point:
            point = True
        elif byte >= 48 and byte <= 57:
            value = value * 10.0 + Float64(Int(byte) - 48)
            digits += 1
            if point:
                after += 1
        else:
            raise Error("A double-double number holds only digits and a point")
        first = False
    if digits == 0:
        raise Error("A double-double number needs a digit")
    var power = dd(1.0)
    for _ in range(after):
        power = power * 10.0
    value = value / power
    return -value if negative else value


def dd_solve(var a: List[List[DD]], var b: List[DD]) raises -> List[DD]:
    """Solve `A x = b` by Gauss-Jordan elimination with partial pivots.

    Args:
        a: The square matrix, by rows.
        b: The right side, one value for each row.

    Returns:
        The solution x.

    Raises:
        Error: If the matrix is not square, the sizes differ, or a pivot
            is 0.
    """
    var n = len(b)
    if len(a) != n:
        raise Error("A double-double solve needs one row for each value")
    for row in a:
        if len(row) != n:
            raise Error("A double-double solve needs a square matrix")
    for c in range(n):
        var best = c
        for r in range(c + 1, n):
            if dd_abs(a[r][c]) > dd_abs(a[best][c]):
                best = r
        if a[best][c].hi == 0.0:
            raise Error("A double-double solve met a zero pivot")
        if best != c:
            var row = a[c].copy()
            a[c] = a[best].copy()
            a[best] = row^
            var value = b[c]
            b[c] = b[best]
            b[best] = value
        var pivot = a[c][c]
        for r in range(n):
            if r == c:
                continue
            var factor = a[r][c] / pivot
            if factor.hi == 0.0:
                continue
            for j in range(c, n):
                a[r][j] = a[r][j] - factor * a[c][j]
            b[r] = b[r] - factor * b[c]
    var x = List[DD]()
    for i in range(n):
        x.append(b[i] / a[i][i])
    return x^


def dd_inverse(a: List[List[DD]]) raises -> List[List[DD]]:
    """Invert a small square matrix, one column at a time.

    Args:
        a: The matrix, by rows.

    Returns:
        The inverse, by rows.

    Raises:
        Error: If the matrix is not square, or is singular.
    """
    var n = len(a)
    var columns = List[List[DD]]()
    for c in range(n):
        var unit = List[DD]()
        for r in range(n):
            unit.append(dd(1.0) if r == c else dd(0.0))
        columns.append(dd_solve(a.copy(), unit^))
    var out = List[List[DD]]()
    for r in range(n):
        var row = List[DD]()
        for c in range(n):
            row.append(columns[c][r])
        out.append(row^)
    return out^


def _erf(x: DD) raises -> DD:
    """Return erf(x) by its Taylor series, for `|x|` up to about 3."""
    var square = x * x
    var term = x
    var total = x
    var n = 0
    while True:
        n += 1
        term = -(term * square) / Float64(n)
        var part = term / Float64(2 * n + 1)
        total = total + part
        if abs(part.hi) <= 1e-36 * abs(total.hi):
            break
    return total * 2.0 / dd_sqrt(dd_pi())


def dd_normal_quantile(p: DD) raises -> DD:
    """Return the z with P(Z <= z) = p, by Newton steps on the series of
    erf.

    Args:
        p: The probability, from 0.01 to 0.99.

    Returns:
        The quantile z.

    Raises:
        Error: If the probability is outside 0.01 to 0.99.
    """
    if not (p.hi >= 0.01 and p.hi <= 0.99):
        raise Error("A double-double normal quantile needs p in 0.01 to 0.99")
    var root2 = dd_sqrt(dd(2.0))
    var density = 1.0 / dd_sqrt(dd_pi() * 2.0)
    var z = dd(0.0)
    for _ in range(60):
        var cdf = (1.0 + _erf(z / root2)) * 0.5
        var step = (cdf - p) / (density * dd_exp(-(z * z) * 0.5))
        z = z - step
        if abs(step.hi) <= 1e-33 * max(abs(z.hi), 1.0):
            break
    return z
