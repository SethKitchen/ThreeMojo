# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read and write doubles exactly as Python's `float()` and `repr()` do.

Mojo 1.1 does neither exactly. `Float64("9.197485623048047e+17")` gives the
double below the nearest one, and `String(48654528712316664.0)` writes
`4.865452871231666e+16`, which reads back as a different double. A tool that
must reproduce a Python tool's text uses these functions instead. They work
with exact integers and fractions, so they are correct for every double.
"""

from std.math import isinf, isnan, log10

from tools._bigint import BigInt
from tools._fraction import Fraction


def parse_float(text: String) raises -> Float64:
    """Return the double nearest to a decimal number, as `float(text)` does.

    Args:
        text: An optional sign, digits with an optional point, and an
            optional exponent. `inf`, `infinity` and `nan` are accepted in
            any case.

    Returns:
        The nearest double, with ties to even.

    Raises:
        Error: If the text is not a number. A number past the largest double
            is infinite.
    """
    var stripped = String(text.strip())
    var lower = stripped.lower()
    var negative = lower.startswith("-")
    var body = (
        String(lower[byte=1:]) if lower.startswith("-")
        or lower.startswith("+") else lower
    )
    if body == "inf" or body == "infinity":
        return -(Float64.MAX * 2) if negative else Float64.MAX * 2
    if body == "nan":
        return (Float64.MAX * 2) - (Float64.MAX * 2)
    var digits = BigInt(0)
    var ten = BigInt(10)
    var exponent = 0
    var seen = False
    var point = False
    var bytes = body.as_bytes()
    var index = 0
    while index < len(bytes):
        var byte = bytes[index]
        if byte >= 48 and byte <= 57:
            digits = digits * ten + BigInt(Int(byte) - 48)
            seen = True
            if point:
                exponent -= 1
        elif byte == 46 and not point:
            point = True
        elif byte == 95:
            pass
        else:
            break
        index += 1
    if not seen:
        raise Error("could not convert string to float: " + text)
    if index < len(bytes):
        if bytes[index] != 101:
            raise Error("could not convert string to float: " + text)
        exponent += Int(String(body[byte = index + 1 :]))
    var value: Fraction
    if exponent >= 0:
        value = Fraction(digits * ten**exponent)
    else:
        value = Fraction.of(digits, ten ** (-exponent))
    var result = _nearest(value)
    return -result if negative else result


def _round_scaled(value: Fraction, power: Int) raises -> BigInt:
    """Return value * 10**power rounded to an integer, ties to even."""
    var scaled: Fraction
    if power >= 0:
        scaled = value * Fraction(BigInt(10) ** power)
    else:
        scaled = value / Fraction(BigInt(10) ** (-power))
    var parts = scaled.numerator.divmod(scaled.denominator)
    var whole = parts[0].copy()
    var twice = parts[1] * BigInt(2)
    if twice > scaled.denominator or (
        twice == scaled.denominator and whole.is_odd()
    ):
        whole = whole + BigInt(1)
    return whole^


def _nearest(value: Fraction) raises -> Float64:
    """Return the double nearest to a fraction; too large is infinite, as
    `float()` reads a decimal."""
    try:
        return value.to_float()
    except:
        return (
            -(Float64.MAX * 2) if value.numerator.negative else Float64.MAX * 2
        )


def _decimal(digits: BigInt, exponent: Int) raises -> Float64:
    """Return the double nearest to digits * 10**exponent."""
    if exponent >= 0:
        return _nearest(Fraction(digits * BigInt(10) ** exponent))
    return _nearest(Fraction.of(digits, BigInt(10) ** (-exponent)))


def shortest_digits(value: Float64) raises -> Tuple[String, Int]:
    """Return the fewest significant digits that read back as the value,
    and the decimal exponent of the first digit.

    Among strings of that length that read back, the one nearest to the
    value is chosen, as Python's `repr` does.

    Args:
        value: A positive, finite double.

    Returns:
        The digits without trailing zeros, and the exponent E such that the
        value is about 0.d1d2... * 10**(E + 1).

    Raises:
        Error: If the value is not positive and finite.
    """
    var exact = Fraction.from_float(value)
    var estimate = Int(log10(value).__floor__())
    # Correct the estimate so that 10**E <= value < 10**(E + 1).
    while True:
        var low = Fraction(
            BigInt(10) ** estimate
        ) if estimate >= 0 else Fraction.of(
            BigInt(1), BigInt(10) ** (-estimate)
        )
        if exact < low:
            estimate -= 1
            continue
        var high = low * Fraction(10)
        if exact >= high:
            estimate += 1
            continue
        break
    for count in range(1, 18):
        var power = count - 1 - estimate
        var nearest = _round_scaled(exact, power)
        var exponent = estimate
        # Rounding up to 10**count adds a digit: it is 10**(count - 1) at the
        # next exponent.
        if nearest == BigInt(10) ** count:
            nearest = BigInt(10) ** (count - 1)
            exponent += 1
            power -= 1
        var candidates = [
            nearest.copy(),
            nearest - BigInt(1),
            nearest + BigInt(1),
        ]
        var best = -1
        var best_distance = Fraction(0)
        for index in range(3):
            var candidate = candidates[index].copy()
            if (
                candidate.bit_length() == 0
                or candidate.to_string().byte_length() != count
            ):
                continue
            if _decimal(candidate, -power) != value:
                continue
            var place = Fraction(candidate) if power == 0 else (
                Fraction.of(candidate, BigInt(10) ** power) if power
                > 0 else Fraction(candidate * BigInt(10) ** (-power))
            )
            var distance = abs(place - exact)
            if best < 0 or distance < best_distance:
                best = index
                best_distance = distance^
        if best >= 0:
            var text = candidates[best].to_string()
            var end = text.byte_length()
            while end > 1 and text.as_bytes()[end - 1] == 48:
                end -= 1
            return (String(text[byte=:end]), exponent)
    raise Error("no shortest representation")


def python_repr(value: Float64) raises -> String:
    """Return `repr(value)` as CPython writes it.

    The digits are the shortest that read back as the value. The notation is
    fixed for decimal exponents from -4 up to 15, and otherwise scientific,
    with a sign and at least two exponent digits.

    Args:
        value: The double.

    Returns:
        The text: for example `0.1`, `1.0`, `1e+16`, `5e-324`, `-0.0`,
        `inf` or `nan`.

    Raises:
        Error: Never for a double; it signals an internal failure.
    """
    if isnan(value):
        return "nan"
    if isinf(value):
        return "inf" if value > 0 else "-inf"
    var sign = (
        String("-") if value < 0
        or (value == 0 and String(value).startswith("-")) else String()
    )
    if value == 0:
        return sign + "0.0"
    var found = shortest_digits(abs(value))
    var digits = found[0]
    var point = found[1] + 1
    var count = digits.byte_length()
    if point <= -4 or point > 16:
        var mantissa = String(digits[byte=:1])
        if count > 1:
            mantissa += "." + String(digits[byte=1:])
        var exponent = point - 1
        var magnitude = String(abs(exponent))
        if magnitude.byte_length() < 2:
            magnitude = "0" + magnitude
        return (
            sign + mantissa + "e" + ("-" if exponent < 0 else "+") + magnitude
        )
    if point <= 0:
        return sign + "0." + "0" * (-point) + digits
    if point >= count:
        return sign + digits + "0" * (point - count) + ".0"
    return (
        sign + String(digits[byte=:point]) + "." + String(digits[byte=point:])
    )
