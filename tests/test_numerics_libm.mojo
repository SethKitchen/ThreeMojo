# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""`glibc_pow` and `glibc_log` against glibc 2.43 on x86-64, bit for bit.

`assets/numerics/make_libm_cases.py` ran glibc on 8055 powers and 6014
logarithms. The inputs reach each branch of the two functions, and many
are random. Each result must have the same bits on every platform. A NaN
must be a NaN: the sign of the NaN of an invalid operation depends on the
processor.
"""

from std.math import isnan
from std.memory import bitcast
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from extensions.numerics.libm import glibc_log, glibc_pow


def _hex(text: String) raises -> UInt64:
    """Read 16 hexadecimal digits.

    Args:
        text: The digits.

    Returns:
        Their value.

    Raises:
        Error: The text is not 16 hexadecimal digits.
    """
    if text.byte_length() != 16:
        raise Error("not 16 digits: " + text)
    var value: UInt64 = 0
    for byte in text.as_bytes():
        var code = Int(byte)
        var digit: UInt64
        if code >= ord("0") and code <= ord("9"):
            digit = UInt64(code - ord("0"))
        elif code >= ord("a") and code <= ord("f"):
            digit = UInt64(code - ord("a") + 10)
        else:
            raise Error("not a hexadecimal digit: " + text)
        value = (value << 4) | digit
    return value


def _same(got: Float64, want: UInt64) -> Bool:
    """Return whether a result has the bits of glibc, or both are NaN.

    Args:
        got: The result of the port.
        want: The bits of glibc's result.

    Returns:
        True when they agree.
    """
    var expected = bitcast[DType.float64](want)
    if isnan(expected):
        return isnan(got)
    return bitcast[DType.uint64](got) == want


def _cases(word: String) raises -> List[List[UInt64]]:
    """Read the cases of one function.

    Args:
        word: `pow` or `log`.

    Returns:
        The words of each line after the name, as bits.

    Raises:
        Error: The file cannot be read or a line is malformed.
    """
    var text = Path("assets/numerics/libm_cases.txt").read_text()
    var out = List[List[UInt64]]()
    for line in text.splitlines():
        var words = line.split(" ")
        if len(words) == 0 or words[0] != word:
            continue
        var row = List[UInt64]()
        for i in range(1, len(words)):
            row.append(_hex(String(words[i])))
        out.append(row^)
    return out^


def test_pow_matches_glibc() raises:
    """Each power has the bits of glibc's."""
    var cases = _cases("pow")
    assert_equal(len(cases), 8055)
    var wrong = 0
    var first = String()
    for row in cases:
        assert_equal(len(row), 3)
        var x = bitcast[DType.float64](row[0])
        var y = bitcast[DType.float64](row[1])
        var got = glibc_pow(x, y)
        if not _same(got, row[2]):
            if wrong == 0:
                first = String(
                    "pow(", repr(x), ", ", repr(y), ") = ", repr(got)
                )
            wrong += 1
    assert_true(wrong == 0, String(wrong, " powers differ, first ", first))


def test_log_matches_glibc() raises:
    """Each logarithm has the bits of glibc's."""
    var cases = _cases("log")
    assert_equal(len(cases), 6014)
    var wrong = 0
    var first = String()
    for row in cases:
        assert_equal(len(row), 2)
        var x = bitcast[DType.float64](row[0])
        var got = glibc_log(x)
        if not _same(got, row[1]):
            if wrong == 0:
                first = String("log(", repr(x), ") = ", repr(got))
            wrong += 1
    assert_true(wrong == 0, String(wrong, " logarithms differ, first ", first))


def test_hex_rejects_bad_digits() raises:
    """The reader refuses a word that is not 16 hexadecimal digits."""
    var short = False
    try:
        _ = _hex("123")
    except:
        short = True
    assert_true(short)
    var letter = False
    try:
        _ = _hex("000000000000000g")
    except:
        letter = True
    assert_true(letter)


def main() raises:
    """Run the tests."""
    TestSuite.discover_tests[__functions_in_module()]().run()
