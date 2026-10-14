# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Verify exact-input footprint singular values with independent decimal math.

    mojo run -I . tools/reference_texture_axes.mojo docs/fixtures/glsl614/footprint_axes.json

The fixture stores Float32 inputs, not platform-dependent trigonometric
calls. No ThreeMojo library code is imported. Expectations are never
rewritten.

The calculation is the one of the Python `Decimal` reference that this tool
replaces. Every value is an exact fraction. Each operation rounds its exact
result to 100 significant decimal digits, with ties to even, as a `Decimal`
context of precision 100 does. The square root is correctly rounded too.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from loaders.json import parse_json
from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_float import python_repr

comptime PRECISION = 100
"""The significant decimal digits of each rounded result."""


def _ten(exponent: Int) raises -> Fraction:
    """Return 10**exponent for any integer exponent."""
    if exponent >= 0:
        return Fraction(BigInt(10) ** exponent)
    return Fraction.of(BigInt(1), BigInt(10) ** -exponent)


def _digits(value: BigInt) -> Int:
    """Return the decimal digits of a nonzero magnitude."""
    return abs(value).to_string().byte_length()


def _nearest_even(value: Fraction) raises -> BigInt:
    """Round a nonnegative fraction to an integer, with ties to even."""
    var parts = value.numerator.divmod(value.denominator)
    var whole = parts[0].copy()
    var twice = parts[1] * BigInt(2)
    if twice > value.denominator or (
        twice == value.denominator and whole.is_odd()
    ):
        whole = whole + BigInt(1)
    return whole^


def _scale(value: Fraction, low: Int, step: Int) raises -> Int:
    """Return the exponent e with 10**low <= value / 10**(step*e) <
    10**(low+step)."""
    var high = _ten(low + step)
    var exponent = (
        _digits(value.numerator) - _digits(value.denominator) - low
    ) // step
    while value / _ten(step * exponent) >= high:
        exponent += 1
    while value / _ten(step * exponent) < _ten(low):
        exponent -= 1
    return exponent


def rounded(value: Fraction) raises -> Fraction:
    """Round to 100 significant digits, with ties to even.

    Args:
        value: The exact value.

    Returns:
        The rounded value.

    Raises:
        Error: If the arithmetic fails.
    """
    if value.is_zero():
        return value.copy()
    var magnitude = abs(value)
    var exponent = _scale(magnitude, PRECISION - 1, 1)
    var result = Fraction(_nearest_even(magnitude / _ten(exponent))) * _ten(
        exponent
    )
    return -result if value.numerator.negative else result^


def isqrt(value: BigInt) raises -> BigInt:
    """Return the integer square root of a nonnegative integer.

    Args:
        value: The integer.

    Returns:
        The largest integer whose square is at most the value.

    Raises:
        Error: If the value is negative.
    """
    if value.negative:
        raise Error("square root of a negative integer")
    if value.is_zero():
        return BigInt(0)
    var x = BigInt(1) << ((value.bit_length() + 1) // 2 + 1)
    while True:
        var y = (x + value // x) >> 1
        if y >= x:
            return x^
        x = y^


def square_root(value: Fraction) raises -> Fraction:
    """Return the square root, correctly rounded to 100 digits.

    Args:
        value: A nonnegative value.

    Returns:
        The rounded square root.

    Raises:
        Error: If the value is negative.
    """
    if value.numerator.negative:
        raise Error("square root of a negative value")
    if value.is_zero():
        return value.copy()
    # Scale so the root has exactly 100 digits before the point.
    var exponent = _scale(value, 2 * (PRECISION - 1), 2)
    var scaled = value / _ten(2 * exponent)
    var root = isqrt(scaled.numerator // scaled.denominator)
    # Compare the exact root with root + 1/2: (2 root + 1)**2 against 4 x.
    var half = Fraction((root * BigInt(2) + BigInt(1)) ** 2)
    var four = scaled * Fraction(4)
    if four > half or (four == half and root.is_odd()):
        root = root + BigInt(1)
    return Fraction(root) * _ten(exponent)


def float32_exact(value: Float64) raises -> Fraction:
    """Round to Float32 as `struct.pack("<f")` does, and return the exact value.

    Args:
        value: The host value.

    Returns:
        The exact value of the nearest Float32.

    Raises:
        Error: If the value is not finite.
    """
    return Fraction.from_float(Float64(Float32(value)))


def singular_values(inputs: List[Float64]) raises -> Tuple[Fraction, Fraction]:
    """Solve the 2-by-2 Gram characteristic polynomial at 100 digits.

    Args:
        inputs: The matrix entries a, b, c and d.

    Returns:
        The major and the minor singular value.

    Raises:
        Error: If an input is not finite.
    """
    var a = float32_exact(inputs[0])
    var b = float32_exact(inputs[1])
    var c = float32_exact(inputs[2])
    var d = float32_exact(inputs[3])
    var trace = rounded(
        rounded(rounded(rounded(a * a) + rounded(b * b)) + rounded(c * c))
        + rounded(d * d)
    )
    var determinant = rounded(rounded(a * d) - rounded(b * c))
    var four = rounded(rounded(Fraction(4) * determinant) * determinant)
    var discriminant = rounded(rounded(trace * trace) - four)
    if discriminant < Fraction(0):
        discriminant = Fraction(0)
    var major = square_root(
        rounded(rounded(trace + square_root(discriminant)) / Fraction(2))
    )
    var minor = Fraction(0)
    if not major.is_zero():
        minor = rounded(abs(determinant) / major)
    return (major^, minor^)


def parse_decimal(text: String) raises -> Fraction:
    """Read a decimal number exactly, as `Decimal(text)` does.

    Args:
        text: An optional sign, digits with an optional point, and an
            optional exponent.

    Returns:
        The exact value.

    Raises:
        Error: If the text is not a decimal number.
    """
    var bytes = text.as_bytes()
    var index = 0
    var negative = False
    if index < len(bytes) and (
        Int(bytes[index]) == ord("-") or Int(bytes[index]) == ord("+")
    ):
        negative = Int(bytes[index]) == ord("-")
        index += 1
    var digits = String()
    var places = 0
    var point = False
    while index < len(bytes):
        var byte = Int(bytes[index])
        if byte == ord("."):
            if point:
                raise Error("not a decimal number: " + text)
            point = True
        elif byte >= ord("0") and byte <= ord("9"):
            digits += chr(byte)
            if point:
                places += 1
        else:
            break
        index += 1
    if digits.byte_length() == 0:
        raise Error("not a decimal number: " + text)
    var exponent = 0
    if index < len(bytes):
        var byte = Int(bytes[index])
        if byte != ord("e") and byte != ord("E"):
            raise Error("not a decimal number: " + text)
        exponent = Int(String(text[byte = index + 1 :]))
    var value = Fraction(BigInt.parse(digits)) * _ten(exponent - places)
    return -value if negative else value^


def _float32_text(value: Fraction) raises -> String:
    """Return `repr(float32(float(value)))`."""
    return python_repr(Float64(Float32(value.to_float())))


def verify(path: String) raises -> Tuple[Int, String]:
    """Check every case of a fixture.

    Args:
        path: The fixture.

    Returns:
        The exit status and the report.

    Raises:
        Error: If the fixture cannot be read.
    """
    var document = parse_json(Path(path).read_text())
    var cases = document.get(document.root(), "cases")
    var report = String()
    for index in range(document.length(cases)):
        var entry = document.at(cases, index)
        var name = document.string(document.get(entry, "name"))
        var node = document.get(entry, "inputs")
        var inputs = List[Float64]()
        for item in range(document.length(node)):
            inputs.append(document.number(document.at(node, item)))
        var values = singular_values(inputs)
        if values[0] != parse_decimal(
            document.string(document.get(entry, "major"))
        ) or values[1] != parse_decimal(
            document.string(document.get(entry, "minor"))
        ):
            return (
                1,
                report + "Independent expectation differs: " + name + "\n",
            )
        report += (
            "PASS "
            + name
            + ": "
            + _float32_text(values[0])
            + ", "
            + _float32_text(values[1])
            + "\n"
        )
    report += (
        "Verified "
        + String(document.length(cases))
        + " exact-input singular-value fixtures\n"
    )
    return (0, report)


def main() raises:
    var given = argv()
    if len(given) != 2:
        print("usage: reference_texture_axes FIXTURE", file=stderr)
        exit(2)
    var outcome = verify(String(given[1]))
    if outcome[0] != 0:
        var lines = outcome[1].split("\n")
        var last = String(lines[len(lines) - 2])
        print(
            String(
                outcome[1][
                    byte = : outcome[1].byte_length() - last.byte_length() - 1
                ]
            ),
            end="",
        )
        print(last, file=stderr)
    else:
        print(outcome[1], end="")
    exit(outcome[0])
