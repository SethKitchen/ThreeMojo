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
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from tests._spiral_half_error_reference import _reference_half_error
from tools._fraction import Fraction
from tools._sha256 import sha256_hex


comptime _FROZEN = (
    "a076ca24b4f9f940b0e5e20213ed3a2a3fd370f92d0f1bc043f36f9ae5a7edd8"
)


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


def _function(text: String, name: String) raises -> String:
    """Return one top-level function, from its `def` through the next.

    Args:
        text: The source file.
        name: The function name.

    Returns:
        The function text, without a following function.

    Raises:
        Error: If the function is absent.
    """
    var header = "def " + name
    var start = text.find(header)
    if start < 0:
        raise Error("missing " + name)
    var rest = String(text[byte=start:])
    var after = header.byte_length()
    var tail = String(rest[byte=after:])
    var cut = tail.find("\ndef ")
    if cut < 0:
        return rest
    return String(rest[byte = : after + cut])


def _skip_string(text: String, mut index: Int, mark: String):
    """Move `index` past a string that starts at `index`.

    Args:
        text: The source.
        index: The opening quote. It ends on the matching closer.
        mark: One double quote, or three double quotes.
    """
    var bytes = text.as_bytes()
    var size = mark.byte_length()
    index += size
    while index < len(bytes):
        if bytes[index] == 92:
            index += 2
            continue
        var matched = True
        var offset = 0
        while offset < size:
            if (
                index + offset >= len(bytes)
                or bytes[index + offset] != mark.as_bytes()[offset]
            ):
                matched = False
                break
            offset += 1
        if matched:
            index += size
            return
        index += 1


def _name_at(text: String, index: Int) -> String:
    """Return the identifier that starts at `index`.

    Args:
        text: The source.
        index: The first character of the identifier.

    Returns:
        The identifier.
    """
    var bytes = text.as_bytes()
    var end = index + 1
    while end < len(bytes):
        var byte = bytes[end]
        var digit = byte >= 48 and byte <= 57
        var letter = (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
        if not digit and not letter and byte != 95:
            break
        end += 1
    return String(text[byte=index:end])


def _is_name_start(byte: Int) -> Bool:
    """Return whether `byte` can start an identifier.

    Args:
        byte: One source byte.

    Returns:
        True for an ASCII letter or `_`.
    """
    var letter = (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)
    return letter or byte == 95


def _calls(text: String, name: String) -> Int:
    """Count calls of `name` outside strings and comments.

    Args:
        text: A function body.
        name: The callee.

    Returns:
        The number of `name(...)` calls.
    """
    var bytes = text.as_bytes()
    var count = 0
    var index = 0
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 35:
            while index < len(bytes) and bytes[index] != 10:
                index += 1
            continue
        if byte == 34:
            var mark = '"'
            if (
                index + 2 < len(bytes)
                and bytes[index + 1] == 34
                and bytes[index + 2] == 34
            ):
                mark = '"""'
            _skip_string(text, index, mark)
            continue
        if _is_name_start(Int(byte)):
            var found = _name_at(text, index)
            index += found.byte_length()
            if found == name:
                while index < len(bytes) and (
                    bytes[index] == 32
                    or bytes[index] == 9
                    or bytes[index] == 10
                ):
                    index += 1
                if index < len(bytes) and bytes[index] == 40:
                    count += 1
            continue
        index += 1
    return count


def _has_name(text: String, name: String) -> Bool:
    """Return whether `name` occurs outside strings and comments.

    Args:
        text: The source.
        name: The identifier.

    Returns:
        True when the identifier is present.
    """
    var bytes = text.as_bytes()
    var index = 0
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 35:
            while index < len(bytes) and bytes[index] != 10:
                index += 1
            continue
        if byte == 34:
            var mark = '"'
            if (
                index + 2 < len(bytes)
                and bytes[index + 1] == 34
                and bytes[index + 2] == 34
            ):
                mark = '"""'
            _skip_string(text, index, mark)
            continue
        if _is_name_start(Int(byte)):
            var found = _name_at(text, index)
            if found == name:
                return True
            index += found.byte_length()
            continue
        index += 1
    return False


def _compact(text: String) -> String:
    """Return `text` without comments or ASCII whitespace.

    Args:
        text: Source text.

    Returns:
        The remaining characters, in order.
    """
    var bytes = text.as_bytes()
    var out = String()
    var index = 0
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 35:
            while index < len(bytes) and bytes[index] != 10:
                index += 1
            continue
        if byte == 32 or byte == 9 or byte == 10 or byte == 13:
            index += 1
            continue
        out += chr(Int(byte))
        index += 1
    return out


def test_original_full_jet_oracle_is_frozen() raises:
    """The frozen full-Jet file keeps its reviewed digest."""
    var digest = sha256_hex(
        Path("tests/_spiral_full_jet_reference.mojo").read_bytes()
    )
    assert_equal(digest, _FROZEN)


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


def test_tightened_reference_does_not_call_the_production_helper() raises:
    """The half-error file names no production spiral helper."""
    var text = Path("tests/_spiral_half_error_reference.mojo").read_text()
    var forbidden = List[String]()
    forbidden.append("_stored_half")
    forbidden.append("_stored_blend_error")
    forbidden.append("_spiral_expression")
    forbidden.append("_spiral_jet")
    for name in forbidden:
        assert_true(not _has_name(text, name))
    var spiral = _function(text, "_half_reference_spiral")
    assert_equal(_calls(spiral, "_reference_half"), 5)


def test_union_is_exact_endpoint_reconstruction_from_child_bounds() raises:
    """The child hull builds its interval from the two rounded endpoints."""
    var text = Path("tests/_spiral_half_error_reference.mojo").read_text()
    var hull = _function(text, "_independent_child_hull")
    assert_true(not _has_name(hull, "_union_points"))
    assert_true(not _has_name(hull, "_full_union_points"))
    assert_true(_compact(hull).find(".hull") < 0)
    var body = _compact(hull)
    var expected = (
        "return_FullJet(_Interval(min(first.low,second.low),"
        + "max(first.high,second.high)),_Interval.whole(),_Interval.whole(),0.0,)"
    )
    assert_true(body.find(expected) >= 0)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
