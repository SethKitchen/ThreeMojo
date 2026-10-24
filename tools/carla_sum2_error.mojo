# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Independent rational Sum2 bound for materialized Float64 terms.

    carla_sum2_error MAG_NUM MAG_DEN INH_NUM INH_DEN COUNT

The five arguments are decimal integers. The program prints the exact
bound as `n/d`, or `n` when the denominator is 1, matching
`str(Fraction)`. The formula requires nearest rounding, gradual
underflow, no reassociation, and no intermediate overflow.
"""

from std.sys import argv, exit, stderr

from tools._bigint import BigInt
from tools._fraction import Fraction


def sum2_error(
    magnitude: Fraction, inherited: Fraction, count: Int
) raises -> Fraction:
    """Return the exact Sum2 majorant for one materialized sum.

    Args:
        magnitude: A bound on the sum of absolute rounded terms.
        inherited: A bound on the sum of inherited term errors.
        count: The number of materialized terms, from 1 through 2**30.

    Returns:
        `inherited` when the magnitude is zero or the count is one.
        Otherwise `inherited + (u + gamma**2) * magnitude`, with
        `u = 2**-53` and `gamma = (count - 1) * u / (1 - (count - 1) * u)`.

    Raises:
        Error: If the count or either majorant is outside the reviewed
            range.
    """
    if count < 1 or count > 1073741824:
        raise Error("unsupported Sum2 count")
    var cap = Fraction(BigInt.power_of_two(900))
    if magnitude < Fraction(0) or magnitude > cap or inherited < Fraction(0):
        raise Error("unsupported Sum2 majorant")
    if magnitude.is_zero() or count == 1:
        return inherited.copy()
    var unit = Fraction.of(BigInt(1), BigInt.power_of_two(53))
    var steps = Fraction(count - 1)
    var nu = steps * unit
    if not nu < Fraction(1):
        raise Error("nonpositive Sum2 gamma denominator")
    var gamma = nu / (Fraction(1) - nu)
    var square = gamma * gamma.copy()
    var extra = (unit + square) * magnitude
    return inherited + extra


def main() raises:
    """Print the Sum2 bound for the five decimal arguments."""
    var arguments = argv()
    if len(arguments) != 6:
        print(
            "usage: carla_sum2_error MAG_NUM MAG_DEN INH_NUM INH_DEN COUNT",
            file=stderr,
        )
        exit(2)
    try:
        var magnitude = Fraction.of(
            BigInt.parse(arguments[1]), BigInt.parse(arguments[2])
        )
        var inherited = Fraction.of(
            BigInt.parse(arguments[3]), BigInt.parse(arguments[4])
        )
        var count = _count(arguments[5])
        print(sum2_error(magnitude, inherited, count))
    except error:
        print("carla_sum2_error:", error, file=stderr)
        exit(1)


def _count(text: String) raises -> Int:
    """Return a decimal count, or raise when it is not in range."""
    var value = BigInt.parse(text)
    if value < BigInt(1) or value > BigInt(1073741824):
        raise Error("unsupported Sum2 count")
    return value.to_int()
