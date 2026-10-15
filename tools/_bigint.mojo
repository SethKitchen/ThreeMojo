# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Integers of any size, with the semantics of Python's `int`.

The exact reference tools need integers far past 64 bits: a binary64 value
as a fraction has a 1074-bit denominator. `BigInt` keeps a sign and a
magnitude of 32-bit limbs, least significant first.

Division floors, as Python's `//`, `%` and `divmod` do, and the remainder
has the divisor's sign. A right shift of a negative number also floors.
"""


@fieldwise_init
struct BigInt(Absable, Comparable, Copyable, Movable, Writable):
    """An integer of any size."""

    var negative: Bool
    """True below zero. Zero is never negative."""
    var limbs: List[UInt32]
    """The magnitude in base 2**32, least significant limb first, with no
    leading zero limb. Zero has no limbs."""

    def __init__(out self, value: Int):
        """Make an integer from a machine integer.

        Args:
            value: The value.
        """
        self.negative = value < 0
        self.limbs = List[UInt32]()
        # The magnitude of Int.MIN does not fit an Int, so take it unsigned.
        var magnitude = UInt64(value) if value >= 0 else UInt64(0) - UInt64(
            value
        )
        while magnitude != 0:
            self.limbs.append(UInt32(magnitude & 0xFFFFFFFF))
            magnitude >>= 32

    @staticmethod
    def _make(negative: Bool, var limbs: List[UInt32]) -> BigInt:
        """Return an integer from a sign and limbs, normalized."""
        while len(limbs) > 0 and limbs[len(limbs) - 1] == 0:
            _ = limbs.pop()
        return BigInt(negative and len(limbs) > 0, limbs^)

    @staticmethod
    def power_of_two(exponent: Int) -> BigInt:
        """Return 2**exponent.

        Args:
            exponent: A non-negative exponent.

        Returns:
            The power.
        """
        var limbs = List[UInt32](length=exponent // 32 + 1, fill=0)
        limbs[exponent // 32] = UInt32(1) << UInt32(exponent % 32)
        return BigInt._make(False, limbs^)

    @staticmethod
    def parse(text: String) raises -> BigInt:
        """Read a decimal integer, with an optional sign.

        Args:
            text: The digits.

        Returns:
            The integer.

        Raises:
            Error: If the text is not a decimal integer.
        """
        var bytes = text.as_bytes()
        var start = 0
        var negative = False
        if len(bytes) > 0 and (bytes[0] == 45 or bytes[0] == 43):
            negative = bytes[0] == 45
            start = 1
        if start >= len(bytes):
            raise Error("not an integer: " + text)
        var value = BigInt(0)
        var ten = BigInt(10)
        for index in range(start, len(bytes)):
            if bytes[index] < 48 or bytes[index] > 57:
                raise Error("not an integer: " + text)
            value = value * ten + BigInt(Int(bytes[index]) - 48)
        return -value if negative else value^

    def is_zero(self) -> Bool:
        """Return whether the integer is zero.

        Returns:
            True for zero.
        """
        return len(self.limbs) == 0

    def bit_length(self) -> Int:
        """Return the bits of the magnitude, as `int.bit_length` does.

        Returns:
            The number of bits, 0 for zero.
        """
        if len(self.limbs) == 0:
            return 0
        var top = self.limbs[len(self.limbs) - 1]
        var bits = 0
        while top != 0:
            bits += 1
            top >>= 1
        return (len(self.limbs) - 1) * 32 + bits

    def trailing_zeros(self) -> Int:
        """Return the number of zero bits below the lowest set bit.

        Returns:
            The count, 0 for zero.
        """
        for index in range(len(self.limbs)):
            var limb = self.limbs[index]
            if limb != 0:
                var bits = 0
                while limb & 1 == 0:
                    limb >>= 1
                    bits += 1
                return index * 32 + bits
        return 0

    def is_odd(self) -> Bool:
        """Return whether the integer is odd.

        Returns:
            True for an odd integer.
        """
        return len(self.limbs) > 0 and self.limbs[0] & 1 == 1

    def to_int(self) raises -> Int:
        """Return the value as a machine integer.

        Returns:
            The value.

        Raises:
            Error: If the value does not fit 64 signed bits.
        """
        if len(self.limbs) > 2:
            raise Error("integer too large for Int")
        var magnitude = UInt64(0)
        for index in range(len(self.limbs) - 1, -1, -1):
            magnitude = (magnitude << 32) | UInt64(self.limbs[index])
        if self.negative:
            if magnitude > UInt64(1) << 63:
                raise Error("integer too large for Int")
            return Int(UInt64(0) - magnitude)
        if magnitude >= UInt64(1) << 63:
            raise Error("integer too large for Int")
        return Int(magnitude)

    def bit(self, index: Int) -> Bool:
        """Return one bit of the magnitude.

        Args:
            index: The bit, 0 for the lowest.

        Returns:
            True when the bit is set.
        """
        var limb = index // 32
        if limb >= len(self.limbs):
            return False
        return (self.limbs[limb] >> UInt32(index % 32)) & 1 == 1

    def to_float(self) -> Float64:
        """Return the nearest Float64, with ties to even, as `float(int)`
        does. A value past the largest double is infinite.

        Returns:
            The value.
        """
        var bits = self.bit_length()
        if bits == 0:
            return 0.0
        var value: Float64
        if bits <= 53:
            value = Float64(self.to_int_unchecked())
        else:
            var shift = bits - 53
            var top = (abs(self) >> shift).to_int_unchecked()
            var half = self.bit(shift - 1)
            var sticky = self.trailing_zeros() < shift - 1
            if half and (sticky or top & 1 == 1):
                top += 1
            value = Float64(top)
            var rest = shift
            while rest > 0 and value < Float64.MAX:
                var step = min(rest, 60)
                value *= Float64(1 << step)
                rest -= step
        return -value if self.negative else value

    def to_int_unchecked(self) -> Int:
        """Return the low 63 bits of the magnitude as an Int.

        Returns:
            The value, for a magnitude known to fit.
        """
        var magnitude = UInt64(0)
        for index in range(min(len(self.limbs), 2) - 1, -1, -1):
            magnitude = (magnitude << 32) | UInt64(self.limbs[index])
        return Int(magnitude & 0x7FFFFFFFFFFFFFFF)

    def write_to(self, mut writer: Some[Writer]):
        """Write the decimal digits.

        Args:
            writer: The destination.
        """
        writer.write(self.to_string())

    def to_string(self) -> String:
        """Return the decimal digits, as `str(int)` does.

        Returns:
            The digits, with a minus sign below zero.
        """
        if len(self.limbs) == 0:
            return "0"
        var chunks = List[UInt32]()
        var limbs = self.limbs.copy()
        while len(limbs) > 0:
            var remainder = UInt64(0)
            for index in range(len(limbs) - 1, -1, -1):
                var current = (remainder << 32) | UInt64(limbs[index])
                limbs[index] = UInt32(current // 1000000000)
                remainder = current % 1000000000
            chunks.append(UInt32(remainder))
            while len(limbs) > 0 and limbs[len(limbs) - 1] == 0:
                _ = limbs.pop()
        var text = String("-") if self.negative else String()
        text += String(chunks[len(chunks) - 1])
        for index in range(len(chunks) - 2, -1, -1):
            var digits = String(chunks[index])
            text += "0" * (9 - digits.byte_length()) + digits
        return text^

    # --- comparison ----------------------------------------------------------

    @staticmethod
    def _compare_magnitude(a: List[UInt32], b: List[UInt32]) -> Int:
        """Return -1, 0 or 1 as |a| is below, at or above |b|."""
        if len(a) != len(b):
            return -1 if len(a) < len(b) else 1
        for index in range(len(a) - 1, -1, -1):
            if a[index] != b[index]:
                return -1 if a[index] < b[index] else 1
        return 0

    def compare(self, other: BigInt) -> Int:
        """Return -1, 0 or 1 as self is below, equal to or above other.

        Args:
            other: The other integer.

        Returns:
            The order.
        """
        if self.negative != other.negative:
            return -1 if self.negative else 1
        var order = BigInt._compare_magnitude(self.limbs, other.limbs)
        return -order if self.negative else order

    def __eq__(self, other: BigInt) -> Bool:
        """Return whether the integers are equal."""
        return self.compare(other) == 0

    def __ne__(self, other: BigInt) -> Bool:
        """Return whether the integers differ."""
        return self.compare(other) != 0

    def __lt__(self, other: BigInt) -> Bool:
        """Return whether self is below other."""
        return self.compare(other) < 0

    def __le__(self, other: BigInt) -> Bool:
        """Return whether self is at most other."""
        return self.compare(other) <= 0

    def __gt__(self, other: BigInt) -> Bool:
        """Return whether self is above other."""
        return self.compare(other) > 0

    def __ge__(self, other: BigInt) -> Bool:
        """Return whether self is at least other."""
        return self.compare(other) >= 0

    # --- arithmetic ----------------------------------------------------------

    @staticmethod
    def _add_magnitude(a: List[UInt32], b: List[UInt32]) -> List[UInt32]:
        """Return |a| + |b|."""
        var out = List[UInt32](capacity=max(len(a), len(b)) + 1)
        var carry = UInt64(0)
        for index in range(max(len(a), len(b))):
            var total = carry
            if index < len(a):
                total += UInt64(a[index])
            if index < len(b):
                total += UInt64(b[index])
            out.append(UInt32(total & 0xFFFFFFFF))
            carry = total >> 32
        if carry != 0:
            out.append(UInt32(carry))
        return out^

    @staticmethod
    def _subtract_magnitude(a: List[UInt32], b: List[UInt32]) -> List[UInt32]:
        """Return |a| - |b|, for |a| at least |b|."""
        var out = List[UInt32](capacity=len(a))
        var borrow = Int64(0)
        for index in range(len(a)):
            var difference = Int64(a[index]) - borrow
            if index < len(b):
                difference -= Int64(b[index])
            if difference < 0:
                difference += Int64(1) << 32
                borrow = 1
            else:
                borrow = 0
            out.append(UInt32(difference))
        return out^

    def __neg__(self) -> BigInt:
        """Return -self."""
        return BigInt._make(not self.negative, self.limbs.copy())

    def __abs__(self) -> BigInt:
        """Return |self|."""
        return BigInt._make(False, self.limbs.copy())

    def __add__(self, other: BigInt) -> BigInt:
        """Return self + other."""
        if self.negative == other.negative:
            return BigInt._make(
                self.negative, BigInt._add_magnitude(self.limbs, other.limbs)
            )
        var order = BigInt._compare_magnitude(self.limbs, other.limbs)
        if order == 0:
            return BigInt(0)
        if order > 0:
            return BigInt._make(
                self.negative,
                BigInt._subtract_magnitude(self.limbs, other.limbs),
            )
        return BigInt._make(
            other.negative, BigInt._subtract_magnitude(other.limbs, self.limbs)
        )

    def __sub__(self, other: BigInt) -> BigInt:
        """Return self - other."""
        return self + (-other)

    def __mul__(self, other: BigInt) -> BigInt:
        """Return self * other."""
        if len(self.limbs) == 0 or len(other.limbs) == 0:
            return BigInt(0)
        var out = List[UInt32](
            length=len(self.limbs) + len(other.limbs), fill=0
        )
        for i in range(len(self.limbs)):
            var carry = UInt64(0)
            var a = UInt64(self.limbs[i])
            for j in range(len(other.limbs)):
                var total = (
                    a * UInt64(other.limbs[j]) + UInt64(out[i + j]) + carry
                )
                out[i + j] = UInt32(total & 0xFFFFFFFF)
                carry = total >> 32
            var k = i + len(other.limbs)
            while carry != 0:
                var total = UInt64(out[k]) + carry
                out[k] = UInt32(total & 0xFFFFFFFF)
                carry = total >> 32
                k += 1
        return BigInt._make(self.negative != other.negative, out^)

    def __lshift__(self, shift: Int) -> BigInt:
        """Return self * 2**shift.

        Args:
            shift: A non-negative bit count.
        """
        if len(self.limbs) == 0 or shift == 0:
            return self.copy()
        var whole = shift // 32
        var bits = UInt32(shift % 32)
        var out = List[UInt32](length=whole, fill=0)
        var carry = UInt32(0)
        for limb in self.limbs:
            if bits == 0:
                out.append(limb)
            else:
                out.append((limb << bits) | carry)
                carry = limb >> (32 - bits)
        if carry != 0:
            out.append(carry)
        return BigInt._make(self.negative, out^)

    def __rshift__(self, shift: Int) -> BigInt:
        """Return floor(self / 2**shift), as Python's `>>` does.

        Args:
            shift: A non-negative bit count.
        """
        if len(self.limbs) == 0 or shift == 0:
            return self.copy()
        var whole = shift // 32
        var bits = UInt32(shift % 32)
        var out = List[UInt32]()
        for index in range(whole, len(self.limbs)):
            var limb = self.limbs[index] >> bits
            if bits != 0 and index + 1 < len(self.limbs):
                limb |= self.limbs[index + 1] << (32 - bits)
            out.append(limb)
        var result = BigInt._make(False, out^)
        if self.negative:
            # Flooring rounds a negative value with lost bits down.
            var lost = self.trailing_zeros() < shift
            result = -result
            if lost:
                result = result - BigInt(1)
        return result^

    @staticmethod
    def _divide_magnitude(
        u_in: List[UInt32], v_in: List[UInt32]
    ) -> Tuple[List[UInt32], List[UInt32]]:
        """Return the quotient and remainder of |u| / |v|, for a non-zero v.

        Knuth's algorithm D, as Warren's `divmnu` writes it.
        """
        var n = len(v_in)
        var m = len(u_in) - n
        if m < 0:
            return (List[UInt32](), u_in.copy())
        if n == 1:
            var divisor = UInt64(v_in[0])
            var quotient = List[UInt32](length=len(u_in), fill=0)
            var remainder = UInt64(0)
            for index in range(len(u_in) - 1, -1, -1):
                var current = (remainder << 32) | UInt64(u_in[index])
                quotient[index] = UInt32(current // divisor)
                remainder = current % divisor
            var rest = List[UInt32]()
            if remainder != 0:
                rest.append(UInt32(remainder))
            return (quotient^, rest^)
        # Normalize so the divisor's top limb has its high bit set.
        var top = v_in[n - 1]
        var s = UInt32(0)
        while top & 0x80000000 == 0:
            top <<= 1
            s += 1
        var vn = List[UInt32](length=n, fill=0)
        for i in range(n - 1, 0, -1):
            vn[i] = (v_in[i] << s) | (
                UInt32(UInt64(v_in[i - 1]) >> UInt64(32 - s)) if s != 0 else 0
            )
        vn[0] = v_in[0] << s
        var un = List[UInt32](length=len(u_in) + 1, fill=0)
        un[len(u_in)] = (
            UInt32(UInt64(u_in[len(u_in) - 1]) >> UInt64(32 - s)) if s
            != 0 else 0
        )
        for i in range(len(u_in) - 1, 0, -1):
            un[i] = (u_in[i] << s) | (
                UInt32(UInt64(u_in[i - 1]) >> UInt64(32 - s)) if s != 0 else 0
            )
        un[0] = u_in[0] << s
        var q = List[UInt32](length=m + 1, fill=0)
        var base = UInt64(1) << 32
        for j in range(m, -1, -1):
            var numerator = (UInt64(un[j + n]) << 32) | UInt64(un[j + n - 1])
            var qhat = numerator // UInt64(vn[n - 1])
            var rhat = numerator % UInt64(vn[n - 1])
            while qhat >= base or qhat * UInt64(vn[n - 2]) > (
                (rhat << 32) | UInt64(un[j + n - 2])
            ):
                qhat -= 1
                rhat += UInt64(vn[n - 1])
                if rhat >= base:
                    break
            var k = Int64(0)
            var t: Int64
            for i in range(n):
                var p = qhat * UInt64(vn[i])
                t = Int64(un[i + j]) - k - Int64(p & 0xFFFFFFFF)
                un[i + j] = UInt32(UInt64(t) & 0xFFFFFFFF)
                k = Int64(p >> 32) - (t >> 32)
            t = Int64(un[j + n]) - k
            un[j + n] = UInt32(UInt64(t) & 0xFFFFFFFF)
            q[j] = UInt32(qhat)
            if t < 0:
                q[j] = q[j] - 1
                var carry = UInt64(0)
                for i in range(n):
                    var total = UInt64(un[i + j]) + UInt64(vn[i]) + carry
                    un[i + j] = UInt32(total & 0xFFFFFFFF)
                    carry = total >> 32
                un[j + n] = UInt32((UInt64(un[j + n]) + carry) & 0xFFFFFFFF)
        var r = List[UInt32](length=n, fill=0)
        for i in range(n):
            r[i] = (un[i] >> s) | (
                UInt32(UInt64(un[i + 1]) << UInt64(32 - s)) if s != 0 else 0
            )
        return (q^, r^)

    def divmod(self, other: BigInt) raises -> Tuple[BigInt, BigInt]:
        """Return the floored quotient and the remainder, as `divmod` does.

        Args:
            other: The divisor.

        Returns:
            The quotient q = floor(self / other), and self - q * other, which
            has the divisor's sign.

        Raises:
            Error: If the divisor is zero.
        """
        if len(other.limbs) == 0:
            raise Error("integer division by zero")
        var parts = BigInt._divide_magnitude(self.limbs, other.limbs)
        var quotient = BigInt._make(
            self.negative != other.negative, parts[0].copy()
        )
        var remainder = BigInt._make(self.negative, parts[1].copy())
        if not remainder.is_zero() and self.negative != other.negative:
            quotient = quotient - BigInt(1)
            remainder = remainder + other
        return (quotient^, remainder^)

    def __floordiv__(self, other: BigInt) raises -> BigInt:
        """Return floor(self / other)."""
        return self.divmod(other)[0].copy()

    def __mod__(self, other: BigInt) raises -> BigInt:
        """Return the remainder with the divisor's sign."""
        return self.divmod(other)[1].copy()

    def __pow__(self, exponent: Int) -> BigInt:
        """Return self ** exponent, for a non-negative exponent."""
        var result = BigInt(1)
        var base = self.copy()
        var rest = exponent
        while rest > 0:
            if rest & 1 == 1:
                result = result * base
            base = base * base
            rest >>= 1
        return result^


def gcd(a: BigInt, b: BigInt) raises -> BigInt:
    """Return the greatest common divisor of |a| and |b|, as `math.gcd` does.

    A power of two shares only its factors of two, so that case takes a
    shift and not Euclid's divisions.

    Args:
        a: An integer.
        b: An integer.

    Returns:
        The non-negative greatest common divisor; gcd(0, 0) is 0.
    """
    var x = abs(a)
    var y = abs(b)
    if x.is_zero():
        return y^
    if y.is_zero():
        return x^
    var x_zeros = x.trailing_zeros()
    var y_zeros = y.trailing_zeros()
    if (x >> x_zeros) == BigInt(1) or (y >> y_zeros) == BigInt(1):
        return BigInt.power_of_two(min(x_zeros, y_zeros))
    while not y.is_zero():
        var rest = x % y
        x = y^
        y = rest^
    return x^
