# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""What the lane report tools share: where they run and write, and
mpmath's text of an exact number.

`carla_pose_report` and `carla_rounding_bound` print numbers as
`mpmath.nstr` prints them, so their reports match the Python tools they
replace.
"""

from std.os.path import exists

from tools._bigint import BigInt
from tools._fraction import Fraction


def repository_root(start: String) raises -> String:
    """Return the repository that contains the lane-oracle constants.

    Args:
        start: A directory inside the repository, or the repository itself.

    Returns:
        The repository root.

    Raises:
        Error: If the walk does not find the constants file.
    """
    var directory = start
    while True:
        if exists(directory + "/tools/fixtures/carla_lane_constants.json"):
            return directory
        var slash = directory.rfind("/")
        if slash <= 0:
            raise Error("cannot find the lane-oracle constants")
        var parent = String(directory[byte=:slash])
        directory = parent


def output_directory(root: String, output_env: String) -> String:
    """Return the directory that receives the pose report.

    Args:
        root: The repository root.
        output_env: `CARLA_LANE_ORACLE_OUTPUT`, or empty when it is unset.

    Returns:
        The environment value, or `root/out/carla-lane-oracle`.
    """
    if output_env.byte_length() == 0:
        return root + "/out/carla-lane-oracle"
    return output_env


def _min_fixed(dps: Int) -> Int:
    """Return mpmath's default `min_fixed` for `dps` digits."""
    var third = -(dps // 3)
    if third < -5:
        return third
    return -5


def _ten_le(exponent: Int, numer: BigInt, denom: BigInt) raises -> Bool:
    """Return whether 10^exponent <= numer/denom."""
    if exponent >= 0:
        return (BigInt(10) ** exponent) * denom <= numer
    return denom <= numer * (BigInt(10) ** (-exponent))


def _floor_log10(numer: BigInt, denom: BigInt) raises -> Int:
    """Return floor(log10(numer/denom))."""
    var bits = numer.bit_length() - denom.bit_length()
    var exponent = bits * 30103 // 100000
    if _ten_le(exponent, numer, denom):
        while _ten_le(exponent + 1, numer, denom):
            exponent += 1
    else:
        while not _ten_le(exponent, numer, denom):
            exponent -= 1
    return exponent


def _place_digits(
    text: String, count: Int, exponent: Int
) -> Tuple[String, Int]:
    """Fit `text` to `count` digits and adjust the exponent."""
    if text.byte_length() > count:
        var extra = text.byte_length() - count
        var trimmed = String(text[byte=:count])
        return (trimmed^, exponent + extra)
    if text.byte_length() < count:
        var padded = "0" * (count - text.byte_length()) + text
        return (padded^, exponent)
    return (String(text), exponent)


def _round_significant(digits: String, dps: Int) -> Tuple[String, Int]:
    """Round `digits` to `dps` places. The integer is 1 when the exponent grows.
    """
    var marker = String(digits[byte = dps : dps + 1])
    var round_up = (
        marker == "5"
        or marker == "6"
        or marker == "7"
        or marker == "8"
        or marker == "9"
    )
    if not round_up:
        var kept = String(digits[byte=:dps])
        return (kept^, 0)
    var raw = String(digits[byte=:dps]).as_bytes()
    var values = List[Int]()
    for index in range(len(raw)):
        values.append(Int(raw[index]) - 48)
    var cursor = len(values) - 1
    while cursor >= 0 and values[cursor] == 9:
        values[cursor] = 0
        cursor -= 1
    if cursor >= 0:
        values[cursor] += 1
        var out = String()
        for value in values:
            out += chr(value + 48)
        return (out^, 0)
    var carried = String("1")
    var zeros = dps - 1
    while zeros > 0:
        carried += "0"
        zeros -= 1
    return (carried^, 1)


def _strip_zeros(text: String) -> String:
    """Drop trailing zeros and keep one digit after a final point."""
    var end = text.byte_length()
    var raw = text.as_bytes()
    while end > 0 and Int(raw[end - 1]) == 48:
        end -= 1
    var kept = String(text[byte=:end])
    if kept.byte_length() == 0:
        return "0"
    var last = String(kept[byte = kept.byte_length() - 1 : kept.byte_length()])
    if last == ".":
        kept += "0"
    return kept^


def nstr(value: Fraction, dps: Int) raises -> String:
    """Return `mpmath.nstr` of an exact fraction.

    Args:
        value: The exact value.
        dps: The number of significant digits.

    Returns:
        The decimal text.

    Raises:
        Error: If a power or a quotient cannot be formed.
    """
    if value.is_zero():
        return "0.0"
    var sign = String("-") if value.numerator.negative else String()
    var numer = abs(value.numerator)
    var denom = value.denominator.copy()
    var exponent = _floor_log10(numer, denom)
    var count = dps + 3
    var power = count - 1 - exponent
    var digits_int: BigInt
    if power >= 0:
        digits_int = (numer * (BigInt(10) ** power)) // denom
    else:
        digits_int = numer // (denom * (BigInt(10) ** (-power)))
    var placed = _place_digits(digits_int.to_string(), count, exponent)
    var rounded = _round_significant(placed[0], dps)
    exponent = placed[1] + rounded[1]
    var digits = rounded[0]
    var split = 1
    if _min_fixed(dps) < exponent and exponent < dps:
        if exponent < 0:
            var padded = "0" * (-exponent) + digits
            digits = padded
        else:
            split = exponent + 1
        exponent = 0
    var whole = String(digits[byte=:split])
    var frac = String(digits[byte=split:])
    var body = _strip_zeros(whole + "." + frac)
    if exponent == 0:
        return sign + body
    if exponent > 0:
        return sign + body + "e+" + String(exponent)
    return sign + body + "e" + String(exponent)


def isqrt(value: BigInt) raises -> BigInt:
    """Return the floor of the square root of an integer.

    Args:
        value: The integer, zero or more.

    Returns:
        The largest integer whose square is at most `value`.

    Raises:
        Error: If `value` is negative.
    """
    if value.is_zero():
        return BigInt(0)
    if value.negative:
        raise Error("square root of a negative integer")
    var x = BigInt.power_of_two((value.bit_length() + 1) // 2)
    while True:
        var y = (x + value // x) >> 1
        if y >= x:
            return x^
        x = y^
