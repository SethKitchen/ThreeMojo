# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Exact rationals with the semantics of Python's `fractions.Fraction`.

A `Fraction` is always in lowest terms with a positive denominator, so its
`numerator` and `denominator` are those Python reports. Floor division and
the remainder floor, as Python's do. `to_float` rounds the exact quotient to
the nearest double with ties to even, as `float(Fraction)` does.
"""

from std.ffi import c_int, external_call
from std.memory import bitcast

from tools._bigint import BigInt, gcd


@fieldwise_init
struct Fraction(Absable, Comparable, Copyable, Movable, Writable):
    """An exact rational number."""

    var numerator: BigInt
    """The numerator, which carries the sign."""
    var denominator: BigInt
    """The denominator, always positive."""

    def __init__(out self, value: Int):
        """Make an integer fraction.

        Args:
            value: The integer.
        """
        self.numerator = BigInt(value)
        self.denominator = BigInt(1)

    def __init__(out self, value: BigInt):
        """Make an integer fraction.

        Args:
            value: The integer.
        """
        self.numerator = value.copy()
        self.denominator = BigInt(1)

    @staticmethod
    def of(numerator: BigInt, denominator: BigInt) raises -> Fraction:
        """Return numerator / denominator in lowest terms.

        Args:
            numerator: The numerator.
            denominator: A non-zero denominator.

        Returns:
            The fraction.

        Raises:
            Error: If the denominator is zero.
        """
        if denominator.is_zero():
            raise Error("Fraction(" + numerator.to_string() + ", 0)")
        var common = gcd(numerator, denominator)
        var top = numerator // common
        var bottom = denominator // common
        if bottom.negative:
            top = -top
            bottom = -bottom
        return Fraction(top^, bottom^)

    @staticmethod
    def from_float(value: Float64) raises -> Fraction:
        """Return a finite double exactly, as `Fraction(float)` does.

        Args:
            value: A finite double.

        Returns:
            The fraction equal to the double.

        Raises:
            Error: If the value is not finite.
        """
        if value != value or value - value != 0:
            raise Error("cannot convert a non-finite float to a Fraction")
        var bits = bitcast[DType.uint64](value)
        var field = Int((bits >> 52) & 0x7FF)
        var significand = Int(bits & 0xFFFFFFFFFFFFF)
        # A normal double has an implicit leading one; a subnormal has none.
        if field != 0:
            significand |= 1 << 52
        var power = max(field, 1) - 1075
        var magnitude = BigInt(significand)
        var result: Fraction
        if power >= 0:
            result = Fraction(magnitude << power)
        else:
            result = Fraction.of(magnitude, BigInt.power_of_two(-power))
        return -result if bits >> 63 == 1 else result^

    def is_zero(self) -> Bool:
        """Return whether the fraction is zero.

        Returns:
            True for zero.
        """
        return self.numerator.is_zero()

    def write_to(self, mut writer: Some[Writer]):
        """Write `n/d`, or `n` for an integer, as `str(Fraction)` does.

        Args:
            writer: The destination.
        """
        writer.write(self.numerator.to_string())
        if self.denominator != BigInt(1):
            writer.write("/", self.denominator.to_string())

    def to_float(self) raises -> Float64:
        """Return the nearest double, with ties to even, as `float()` does.

        Returns:
            The double, subnormal when it must be.

        Raises:
            Error: If the value is too large for a double.
        """
        if self.numerator.is_zero():
            return 0.0
        var a = abs(self.numerator)
        var b = self.denominator.copy()
        # Choose 2**shift so the quotient has 55 or 56 bits: two to round
        # with and one more for the possible carry.
        var shift = a.bit_length() - b.bit_length() - 55
        var quotient: BigInt
        var remainder: BigInt
        if shift >= 0:
            var parts = a.divmod(b << shift)
            quotient = parts[0].copy()
            remainder = parts[1].copy()
        else:
            var parts = (a << -shift).divmod(b)
            quotient = parts[0].copy()
            remainder = parts[1].copy()
        # Drop bits to keep 53, or fewer below the normal range.
        var drop = max(quotient.bit_length() - 53, -1074 - shift)
        var kept = quotient >> drop if drop > 0 else quotient.copy()
        if drop > 0:
            var half = quotient.bit(drop - 1)
            var sticky = (
                not remainder.is_zero() or quotient.trailing_zeros() < drop - 1
            )
            if half and (sticky or kept.is_odd()):
                kept = kept + BigInt(1)
        var exponent = shift + max(drop, 0)
        if kept.bit_length() + exponent > 1024:
            raise Error("integer division result too large for a float")
        var value = external_call["ldexp", Float64](
            Float64(kept.to_int_unchecked()), c_int(exponent)
        )
        return -value if self.numerator.negative else value

    # --- comparison ----------------------------------------------------------

    def compare(self, other: Fraction) -> Int:
        """Return -1, 0 or 1 as self is below, equal to or above other.

        Args:
            other: The other fraction.

        Returns:
            The order.
        """
        return (self.numerator * other.denominator).compare(
            other.numerator * self.denominator
        )

    def __eq__(self, other: Fraction) -> Bool:
        """Return whether the fractions are equal."""
        return (
            self.numerator == other.numerator
            and self.denominator == other.denominator
        )

    def __ne__(self, other: Fraction) -> Bool:
        """Return whether the fractions differ."""
        return not self == other

    def __lt__(self, other: Fraction) -> Bool:
        """Return whether self is below other."""
        return self.compare(other) < 0

    def __le__(self, other: Fraction) -> Bool:
        """Return whether self is at most other."""
        return self.compare(other) <= 0

    def __gt__(self, other: Fraction) -> Bool:
        """Return whether self is above other."""
        return self.compare(other) > 0

    def __ge__(self, other: Fraction) -> Bool:
        """Return whether self is at least other."""
        return self.compare(other) >= 0

    # --- arithmetic ----------------------------------------------------------

    def __neg__(self) -> Fraction:
        """Return -self."""
        return Fraction(-self.numerator, self.denominator.copy())

    def __abs__(self) -> Fraction:
        """Return |self|."""
        return Fraction(abs(self.numerator), self.denominator.copy())

    def __add__(self, other: Fraction) raises -> Fraction:
        """Return self + other."""
        if self.denominator == other.denominator:
            return Fraction.of(
                self.numerator + other.numerator, self.denominator
            )
        return Fraction.of(
            self.numerator * other.denominator
            + other.numerator * self.denominator,
            self.denominator * other.denominator,
        )

    def __sub__(self, other: Fraction) raises -> Fraction:
        """Return self - other."""
        return self + (-other)

    def __mul__(self, other: Fraction) raises -> Fraction:
        """Return self * other."""
        return Fraction.of(
            self.numerator * other.numerator,
            self.denominator * other.denominator,
        )

    def __truediv__(self, other: Fraction) raises -> Fraction:
        """Return self / other."""
        if other.is_zero():
            raise Error("Fraction division by zero")
        return Fraction.of(
            self.numerator * other.denominator,
            self.denominator * other.numerator,
        )

    def __floordiv__(self, other: Fraction) raises -> BigInt:
        """Return floor(self / other), an integer, as `//` does."""
        if other.is_zero():
            raise Error("Fraction division by zero")
        return (self.numerator * other.denominator) // (
            self.denominator * other.numerator
        )

    def __mod__(self, other: Fraction) raises -> Fraction:
        """Return self - floor(self / other) * other, as `%` does."""
        return self - Fraction(self // other) * other

    def __pow__(self, exponent: Int) raises -> Fraction:
        """Return self ** exponent; a negative exponent inverts."""
        if exponent >= 0:
            return Fraction(
                self.numerator**exponent, self.denominator**exponent
            )
        if self.is_zero():
            raise Error("Fraction(0) to a negative power")
        var inverse = Fraction.of(self.denominator, self.numerator)
        return Fraction(
            inverse.numerator**-exponent, inverse.denominator**-exponent
        )
