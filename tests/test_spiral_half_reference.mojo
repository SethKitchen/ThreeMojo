# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The native half-error reference matches exact binary rationals.

Every finite exponent is checked. The high endpoint is the successor of the
nearest-even half, and zero and one keep the exact half.
"""

from std.ffi import external_call
from std.math import inf
from std.memory import bitcast
from std.testing import TestSuite, assert_equal, assert_true

from tests._spiral_half_error_reference import _reference_half_error
from tools._fraction import Fraction


def _next_up(value: Float64) -> Float64:
    """Return `math.nextafter(value, math.inf)`.

    Args:
        value: The double.

    Returns:
        The next double toward positive infinity.
    """
    return external_call["nextafter", Float64](value, inf[DType.float64]())


def _bits(value: Float64) -> UInt64:
    """Return the bits of a double.

    Args:
        value: The double.

    Returns:
        The 64 bits.
    """
    return bitcast[DType.uint64](value)


def test_native_word_algorithm_matches_exact_halves_at_every_exponent() raises:
    """Each reviewed mantissa matches `float(Fraction(source) / 2)`."""
    var mantissas = List[UInt64]()
    mantissas.append(0)
    mantissas.append(1)
    mantissas.append(2)
    mantissas.append(3)
    mantissas.append((UInt64(1) << 51) - 1)
    mantissas.append(UInt64(1) << 51)
    mantissas.append((UInt64(1) << 52) - 3)
    mantissas.append((UInt64(1) << 52) - 2)
    mantissas.append((UInt64(1) << 52) - 1)
    var cases = 0
    var exponent = 0
    while exponent < 2047:
        var mantissa_index = 0
        while mantissa_index < len(mantissas):
            var source_word = (UInt64(exponent) << 52) | mantissas[
                mantissa_index
            ]
            var source = bitcast[DType.float64](source_word)
            var exact = Fraction.from_float(source) / Fraction(2)
            var expected = source / 2.0
            if source != 0.0 and source != 1.0:
                expected = _next_up(exact.to_float())
            var actual = _reference_half_error(source)
            assert_equal(_bits(actual), _bits(expected))
            assert_true(Fraction.from_float(actual) >= exact)
            cases += 1
            mantissa_index += 1
        exponent += 1
    assert_equal(cases, 18423)
    assert_equal(_bits(_reference_half_error(-0.0)), UInt64(0))


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
