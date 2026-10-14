# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Generate exact rational controls for the periodic scalar helpers.

    reference_remainders --check
    reference_remainders --write

decodes input bits to exact fractions, takes rational floor division and
subtraction, then rounds directly to the target format with ties to even.
No production code, host `fmod`, floating-point quotient or floating-point
remainder is used. `--check` verifies the saved fixtures in
`assets/math_remainder/`; `--write` replaces them.

The cases, and so the fixtures, are those of the Python generator this tool
replaces: the random pairs come from `random.Random(603 + fraction bits)`.
"""

from std.collections import Set
from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_random import PythonRandom


def exact(
    bits: UInt64, fraction_bits: Int, exponent_bits: Int
) raises -> Fraction:
    """Decode a finite, positive binary float without a host float.

    Args:
        bits: The float's bits, with a clear sign bit.
        fraction_bits: The stored significand bits: 23 or 52.
        exponent_bits: The exponent bits: 8 or 11.

    Returns:
        The float's exact value.

    Raises:
        Error: If the bits encode an infinity or a NaN.
    """
    var exponent = Int(bits >> UInt64(fraction_bits))
    var significand = Int(bits & ((UInt64(1) << UInt64(fraction_bits)) - 1))
    var bias = (1 << (exponent_bits - 1)) - 1
    if exponent >= (1 << exponent_bits) - 1:
        raise Error("not a finite float")
    if exponent != 0:
        significand |= 1 << fraction_bits
    var power = max(exponent, 1) - bias - fraction_bits
    if power >= 0:
        return Fraction(BigInt(significand) << power)
    return Fraction.of(BigInt(significand), BigInt.power_of_two(-power))


def _power_of_two(exponent: Int) raises -> Fraction:
    """Return 2**exponent for any integer exponent."""
    if exponent >= 0:
        return Fraction(BigInt.power_of_two(exponent))
    return Fraction.of(BigInt(1), BigInt.power_of_two(-exponent))


def rounded(
    value: Fraction, fraction_bits: Int, exponent_bits: Int
) raises -> UInt64:
    """Round a dyadic rational to binary float bits, with ties to even.

    Args:
        value: The value.
        fraction_bits: The stored significand bits.
        exponent_bits: The exponent bits.

    Returns:
        The bits of the nearest float; an overflow is infinite.
    """
    var sign = (
        UInt64(1) << UInt64(fraction_bits + exponent_bits)
    ) if value.numerator.negative else UInt64(0)
    var magnitude = abs(value)
    if magnitude.is_zero():
        return sign
    var bias = (1 << (exponent_bits - 1)) - 1
    var exponent = (
        magnitude.numerator.bit_length() - magnitude.denominator.bit_length()
    )
    if magnitude < _power_of_two(exponent):
        exponent -= 1
    var quantum = max(exponent - fraction_bits, 1 - bias - fraction_bits)
    var scaled = magnitude / _power_of_two(quantum)
    var parts = scaled.numerator.divmod(scaled.denominator)
    var significand = parts[0].copy()
    var twice = parts[1] * BigInt(2)
    if twice > scaled.denominator or (
        twice == scaled.denominator and significand.is_odd()
    ):
        significand = significand + BigInt(1)
    if significand >= BigInt.power_of_two(fraction_bits + 1):
        significand = significand >> 1
        quantum += 1
    var exponent_field = quantum + fraction_bits + bias
    if exponent_field >= (1 << exponent_bits) - 1:
        return sign | (
            UInt64((1 << exponent_bits) - 1) << UInt64(fraction_bits)
        )
    var stored = UInt64(significand.to_int())
    if stored < UInt64(1) << UInt64(fraction_bits):
        return sign | stored
    return (
        sign
        | (UInt64(exponent_field) << UInt64(fraction_bits))
        | (stored - (UInt64(1) << UInt64(fraction_bits)))
    )


def _add(
    mut seen: Set[String],
    mut result: List[Tuple[UInt64, UInt64]],
    n: UInt64,
    m: UInt64,
):
    """Add a pair once, keeping the first order of arrival."""
    var key = String(n) + " " + String(m)
    if not key in seen:
        seen.add(key)
        result.append((n, m))


def pairs(
    fraction_bits: Int, exponent_bits: Int
) raises -> List[Tuple[UInt64, UInt64]]:
    """Return every exponent, mantissa edges, neighbors and random pairs.

    Args:
        fraction_bits: The stored significand bits.
        exponent_bits: The exponent bits.

    Returns:
        The (dividend, divisor) bit pairs, each once, sorted.
    """
    var limit = UInt64((1 << exponent_bits) - 1) << UInt64(fraction_bits)
    var bias = UInt64((1 << (exponent_bits - 1)) - 1)
    var one = UInt64(1) << UInt64(fraction_bits)
    var mantissas = [UInt64(0), UInt64(1), one // 3, one - 1]
    var one_and_half = (bias << UInt64(fraction_bits)) | (
        UInt64(1) << UInt64(fraction_bits - 1)
    )
    var seen = Set[String]()
    var result = List[Tuple[UInt64, UInt64]]()

    var exponents = (1 << exponent_bits) - 1
    for exponent in range(exponents):
        var n = (UInt64(exponent) << UInt64(fraction_bits)) | mantissas[
            exponent % 4
        ]
        var m_exponent = (exponent * 73 + 19) % exponents
        var m = (UInt64(m_exponent) << UInt64(fraction_bits)) | mantissas[
            (exponent + 1) % 4
        ]
        _add(seen, result, n, max(UInt64(1), m))
        _add(seen, result, n, one_and_half)
        # Exact multiples and their adjacent representable inputs.
        m = max(
            UInt64(1),
            (UInt64(exponent) << UInt64(fraction_bits))
            | (UInt64(1) << UInt64(fraction_bits - 1)),
        )
        for near in [m - 1, m, m + 1]:
            if near < limit:
                _add(seen, result, near, m)
    var edges = [
        UInt64(0),
        UInt64(1),
        UInt64(2),
        UInt64(3),
        one - 1,
        one,
        one + 1,
        bias << UInt64(fraction_bits),
        one_and_half,
        (bias + 1) << UInt64(fraction_bits),
        limit - 2,
        limit - 1,
    ]
    for n in edges:
        for m in edges:
            if m != 0:
                _add(seen, result, n, m)
    var generator = PythonRandom(603 + fraction_bits)
    var bound = BigInt(Int(limit))
    for _ in range(512):
        var n = UInt64(generator.randrange(BigInt(0), bound).to_int())
        var m = UInt64(generator.randrange(BigInt(1), bound).to_int())
        _add(seen, result, n, m)
    # Sort as Python sorts tuples: by the first item, then the second.
    var keyed = List[String]()
    for pair in result:
        var first = String(pair[0])
        var second = String(pair[1])
        keyed.append(
            "0" * (20 - first.byte_length())
            + first
            + " "
            + "0" * (20 - second.byte_length())
            + second
        )
    sort(keyed)
    var ordered = List[Tuple[UInt64, UInt64]]()
    for key in keyed:
        var parts = key.split(" ")
        ordered.append(
            (UInt64(Int(String(parts[0]))), UInt64(Int(String(parts[1]))))
        )
    return ordered^


def fixtures32() raises -> String:
    """Return bit-exact modulo and folded-wave controls for both signs.

    Returns:
        One line per pair: the inputs, the remainder, the remainder from the
        other side, and the folded wave and its shift by one period.
    """
    var lines = List[String]()
    for pair in pairs(23, 8):
        var n_bits = pair[0]
        var m_bits = pair[1]
        var n = exact(n_bits, 23, 8)
        var m = exact(m_bits, 23, 8)
        var residual = n - Fraction(n // m) * m
        var same = rounded(residual, 23, 8)
        var opposite = rounded(
            m - residual, 23, 8
        ) if not residual.is_zero() else UInt64(0)
        if opposite >= m_bits:
            opposite = m_bits - 1
        var period = Fraction(2) * m
        var phase = n - Fraction(n // period) * period
        var other = period - phase
        var wave = phase.copy() if phase <= other else other^
        var values = [
            n_bits,
            m_bits,
            same,
            opposite,
            rounded(wave, 23, 8),
            rounded(wave - period, 23, 8),
        ]
        var words = List[String]()
        for value in values:
            words.append(String(value))
        lines.append(" ".join(words))
    return "\n".join(lines) + "\n"


def fixtures64() raises -> String:
    """Return exact binary64 truncating remainder controls.

    Returns:
        One line per pair: the inputs and the remainder.

    Raises:
        Error: If a remainder is not exactly representable.
    """
    var lines = List[String]()
    for pair in pairs(52, 11):
        var n = exact(pair[0], 52, 11)
        var m = exact(pair[1], 52, 11)
        var residual = n - Fraction(n // m) * m
        var bits = rounded(residual, 52, 11)
        if exact(bits, 52, 11) != residual:
            raise Error("an inexact binary64 remainder")
        lines.append(
            String(pair[0]) + " " + String(pair[1]) + " " + String(bits)
        )
    return "\n".join(lines) + "\n"


def run(root: String, write: Bool) raises -> Tuple[Int, String]:
    """Check or write both fixtures.

    Args:
        root: The repository root.
        write: True to replace the fixtures.

    Returns:
        The exit status and the report.
    """
    var report = String()
    for entry in [("periodic32.txt", True), ("remainder64.txt", False)]:
        var contents = fixtures32() if entry[1] else fixtures64()
        var path = "assets/math_remainder/" + entry[0]
        if write:
            Path(root + "/" + path).write_text(contents)
        elif Path(root + "/" + path).read_text() != contents:
            return (1, report + "Fixture differs: " + path + "\n")
        report += (
            entry[0]
            + ": "
            + String(len(contents.split("\n")) - 1)
            + " exact rational cases\n"
        )
    return (0, report)


def main() raises:
    var given = argv()
    if len(given) != 2 or not (
        String(given[1]) == "--check" or String(given[1]) == "--write"
    ):
        print("usage: reference_remainders (--check | --write)", file=stderr)
        exit(2)
    var outcome = run(".", String(given[1]) == "--write")
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
