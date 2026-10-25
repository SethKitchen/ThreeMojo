# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The native Sum2 reference matches exact rationals and the checked bound.

The checked production function is called directly. The environment wrapper
is checked from its source: a failed environment check returns infinity, and
a passing check returns the checked bound.
"""

from std.ffi import external_call
from std.math import inf, isfinite, nan
from std.memory import bitcast
from std.pathlib import Path
from std.testing import TestSuite, assert_equal, assert_true

from extensions.carla.curve_sum2 import _sum2_error_checked
from tests._spiral_sum2_reference import (
    _sum2_reference_add_upper,
    _sum2_reference_error,
)
from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._sha256 import sha256_hex


comptime _FULL_JET = (
    "a076ca24b4f9f940b0e5e20213ed3a2a3fd370f92d0f1bc043f36f9ae5a7edd8"
)
comptime _HALF_ERROR = (
    "76b70a95dace9f5a74da9aedfcbc765a5deb060af3d708e638ef10c10a09ece5"
)
comptime _INFINITY = UInt64(0x7FF0000000000000)


def _bits(value: Float64) -> UInt64:
    """Return the bits of a double.

    Args:
        value: The double.

    Returns:
        The 64 bits.
    """
    return bitcast[DType.uint64](value)


def _float(word: UInt64) -> Float64:
    """Return the double with these bits.

    Args:
        word: The 64 bits.

    Returns:
        The double.
    """
    return bitcast[DType.float64](word)


def _next_up(value: Float64) -> Float64:
    """Return the next double toward positive infinity.

    Args:
        value: The double.

    Returns:
        The successor toward positive infinity.
    """
    return external_call["nextafter", Float64](value, inf[DType.float64]())


def _power(exponent: Int) -> Float64:
    """Return `2**exponent` as a double.

    Args:
        exponent: The power of two, from -1074 through 1023.

    Returns:
        The double. Subnormal powers use the IEEE trailing bit.
    """
    if exponent > 1023:
        return inf[DType.float64]()
    if exponent < -1074:
        return 0.0
    if exponent >= -1022:
        return _float(UInt64(exponent + 1023) << 52)
    return _float(UInt64(1) << UInt64(exponent + 1074))


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
    var search = text
    var skipped = 0
    while True:
        var start = search.find(header)
        if start < 0:
            raise Error("missing " + name)
        var at = skipped + start + header.byte_length()
        var bytes = text.as_bytes()
        if at < len(bytes) and _is_name_start(Int(bytes[at])):
            skipped = at
            search = String(text[byte=at:])
            continue
        var rest = String(text[byte = skipped + start :])
        var tail = String(rest[byte = header.byte_length() :])
        var cut = tail.find("\ndef ")
        if cut < 0:
            return rest
        return String(rest[byte = : header.byte_length() + cut])


def _body(text: String) raises -> String:
    """Return the lines after a `Float64` return signature.

    Args:
        text: One function.

    Returns:
        The body.

    Raises:
        Error: If the signature is absent.
    """
    var mark = "-> Float64:"
    var found = text.find(mark)
    if found < 0:
        raise Error("missing return")
    var rest = String(text[byte = found + mark.byte_length() :])
    var newline = rest.find("\n")
    if newline < 0:
        return String("")
    return String(rest[byte = newline + 1 :])


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


def _invocations(text: String) -> List[String]:
    """Return call and generic names outside strings and comments.

    Args:
        text: A function body.

    Returns:
        Each callee, in source order. An attribute call keeps its receiver.
    """
    var names = List[String]()
    var bytes = text.as_bytes()
    var index = 0
    var qualifier = String("")
    var pending = False
    while index < len(bytes):
        var byte = bytes[index]
        if byte == 35:
            while index < len(bytes) and bytes[index] != 10:
                index += 1
            pending = False
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
            pending = False
            continue
        if _is_name_start(Int(byte)):
            var found = _name_at(text, index)
            index += found.byte_length()
            var look = index
            while look < len(bytes) and (
                bytes[look] == 32 or bytes[look] == 9 or bytes[look] == 10
            ):
                look += 1
            if (
                not _keyword(found)
                and look < len(bytes)
                and (bytes[look] == 40 or bytes[look] == 91)
            ):
                var label = found
                if pending:
                    label = qualifier + "." + found
                names.append(label)
            pending = False
            qualifier = found
            continue
        if byte == 46:
            pending = True
            index += 1
            continue
        pending = False
        index += 1
    return names^


def _keyword(name: String) -> Bool:
    """Return whether `name` introduces syntax rather than a call.

    Args:
        name: An identifier.

    Returns:
        True for a keyword that can stand before a parenthesis.
    """
    if name == "if" or name == "elif" or name == "while" or name == "for":
        return True
    if name == "return" or name == "and" or name == "or" or name == "not":
        return True
    return name == "in" or name == "is"


def _reference_call(name: String) -> Bool:
    """Return whether a reference callee is on the approved list.

    Args:
        name: The callee.

    Returns:
        True for scalar casts, `bitcast`, and the reference helpers.
    """
    if name == "bitcast" or name == "UInt64" or name == "Float64":
        return True
    if name == "_sum2_reference_successor":
        return True
    if name == "_sum2_reference_add_upper":
        return True
    return name == "_sum2_reference_error"


def _production_call(name: String) -> Bool:
    """Return whether a checked-bound callee is on the approved list.

    Args:
        name: The callee.

    Returns:
        True for `Float64`, `isfinite`, `inf`, and `_Interval.point`.
    """
    if name == "Float64" or name == "isfinite" or name == "inf":
        return True
    return name == "_Interval.point"


def _module_name(line: String) -> String:
    """Return the module named by an import line.

    Args:
        line: One source line.

    Returns:
        The module, or an empty string when the line is not an import.
    """
    if line.find("from ") == 0:
        var rest = String(line[byte=5:])
        var cut = rest.find(" import")
        if cut < 0:
            return rest
        return String(rest[byte=:cut])
    if line.find("import ") == 0:
        var rest = String(line[byte=7:])
        var cut = rest.find(" ")
        if cut < 0:
            return rest
        return String(rest[byte=:cut])
    return String("")


def _forbidden_module(name: String) -> Bool:
    """Return whether `name` is a production Sum2 import.

    Args:
        name: A module name.

    Returns:
        True for the production Sum2 modules.
    """
    if name == "extensions.carla.curve_sum2":
        return True
    if name == "extensions.carla.curve_bounds":
        return True
    if name == "extensions.carla.lane_value_bounds":
        return True
    return name == "extensions.carla.spiral_roundoff_proof"


def _unit() raises -> Fraction:
    """Return the double unit roundoff, `2**-53`.

    Returns:
        The fraction.

    Raises:
        Error: If the power of two cannot be built.
    """
    return Fraction.of(BigInt(1), BigInt.power_of_two(53))


def _endpoint_add_high(one: Float64, two: Float64) -> Float64:
    """Return the high endpoint of two point intervals.

    Args:
        one: The first point.
        two: The second point.

    Returns:
        The outward high endpoint. Two zeros use positive zero.
    """
    if one == 0.0 and two == 0.0:
        return 0.0
    if one == 0.0:
        return two
    if two == 0.0:
        return one
    return _next_up(one + two)


def _magnitudes() -> List[Float64]:
    """Return the reviewed magnitude samples.

    Returns:
        Twelve finite samples, including both zeros.
    """
    var values = List[Float64]()
    values.append(0.0)
    values.append(_float(UInt64(1) << 63))
    values.append(_float(1))
    values.append(_float(2))
    values.append(_float(0x000FFFFFFFFFFFFF))
    values.append(_float(0x0010000000000000))
    values.append(_power(-400))
    values.append(1.0)
    values.append(_next_up(1.0))
    values.append(2.0)
    values.append(_power(400))
    values.append(_power(900))
    return values^


def _inherited() -> List[Float64]:
    """Return the reviewed inherited-error samples.

    Returns:
        Seven finite samples, including both zeros.
    """
    var values = List[Float64]()
    values.append(0.0)
    values.append(_float(UInt64(1) << 63))
    values.append(_float(1))
    values.append(_power(-100))
    values.append(_float(0x3D06849B86A12B9B))
    values.append(1.0)
    values.append(_power(1000))
    return values^


def _counts() -> List[Int]:
    """Return the reviewed term counts.

    Returns:
        Nine counts inside the supported range.
    """
    var values = List[Int]()
    values.append(1)
    values.append(2)
    values.append(3)
    values.append(7)
    values.append(10)
    values.append(100)
    values.append(320)
    values.append(65536)
    values.append(1073741824)
    return values^


def test_frozen_full_and_half_references_remain_immutable() raises:
    """The frozen full-Jet and half-error files keep their reviewed digests."""
    var full = sha256_hex(
        Path("tests/_spiral_full_jet_reference.mojo").read_bytes()
    )
    var half = sha256_hex(
        Path("tests/_spiral_half_error_reference.mojo").read_bytes()
    )
    assert_equal(full, _FULL_JET)
    assert_equal(half, _HALF_ERROR)


def test_monotone_upper_matches_the_checked_bound() raises:
    """Each reviewed sample matches `_sum2_error_checked` bit for bit."""
    var counts = _counts()
    var magnitudes = _magnitudes()
    var inherited = _inherited()
    var cases = 0
    for count_index in range(len(counts)):
        var count = counts[count_index]
        for magnitude_index in range(len(magnitudes)):
            var magnitude = magnitudes[magnitude_index]
            for inherited_index in range(len(inherited)):
                var error = inherited[inherited_index]
                var reference = _sum2_reference_error(magnitude, error, count)
                var actual = _sum2_error_checked(magnitude, error, count)
                assert_equal(_bits(reference), _bits(actual))
                cases += 1
    assert_equal(cases, 756)


def test_every_upper_encloses_the_exact_rational_bound() raises:
    """Each reference upper bound is at least the exact rational majorant."""
    var unit = _unit()
    var cases = 0
    var exponent = -1074
    while exponent < 901:
        var magnitude = _power(exponent)
        var counts = List[Int]()
        counts.append(1)
        counts.append(2)
        counts.append(3)
        counts.append(10)
        counts.append(320)
        counts.append(1073741824)
        var errors = List[Float64]()
        errors.append(0.0)
        errors.append(_float(1))
        errors.append(_power(-53))
        errors.append(1.0)
        for count_index in range(len(counts)):
            var count = counts[count_index]
            var terms = Fraction(count - 1) * unit.copy()
            var gamma = terms.copy() / (Fraction(1) - terms.copy())
            for error_index in range(len(errors)):
                var error = errors[error_index]
                var result = _sum2_reference_error(magnitude, error, count)
                var exact = Fraction.from_float(error)
                if count != 1:
                    var factor = unit.copy() + gamma.copy() * gamma.copy()
                    exact = exact + factor * Fraction.from_float(magnitude)
                assert_true(Fraction.from_float(result) >= exact)
                cases += 1
        exponent += 17
    assert_equal(cases, 2808)


def test_guards_and_exact_boundary_words() raises:
    """Rejected inputs are positive infinity, and the boundaries stay exact."""
    var bad_magnitudes = List[Float64]()
    var bad_errors = List[Float64]()
    var bad_counts = List[Int]()
    bad_magnitudes.append(-1.0)
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(inf[DType.float64]())
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(-inf[DType.float64]())
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(nan[DType.float64]())
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(_next_up(_power(900)))
    bad_errors.append(0.0)
    bad_counts.append(2)
    bad_magnitudes.append(1.0)
    bad_errors.append(-1.0)
    bad_counts.append(2)
    bad_magnitudes.append(1.0)
    bad_errors.append(inf[DType.float64]())
    bad_counts.append(2)
    bad_magnitudes.append(1.0)
    bad_errors.append(nan[DType.float64]())
    bad_counts.append(2)
    bad_magnitudes.append(1.0)
    bad_errors.append(0.0)
    bad_counts.append(0)
    bad_magnitudes.append(1.0)
    bad_errors.append(0.0)
    bad_counts.append(-1)
    bad_magnitudes.append(1.0)
    bad_errors.append(0.0)
    bad_counts.append(1073741825)
    var index = 0
    while index < len(bad_counts):
        var magnitude = bad_magnitudes[index]
        var error = bad_errors[index]
        var count = bad_counts[index]
        var reference = _sum2_reference_error(magnitude, error, count)
        var actual = _sum2_error_checked(magnitude, error, count)
        assert_equal(_bits(reference), _INFINITY)
        assert_equal(_bits(actual), _INFINITY)
        index += 1
    assert_equal(_sum2_reference_error(0.0, 3.0, 2), 3.0)
    assert_equal(_sum2_reference_error(_float(UInt64(1) << 63), 3.0, 2), 3.0)
    assert_equal(_sum2_reference_error(1.0, 3.0, 1), 3.0)
    assert_true(isfinite(_sum2_reference_error(_power(900), 0.0, 1073741824)))


def _trim_end(text: String) -> String:
    """Drop trailing spaces and newlines.

    Args:
        text: Source text.

    Returns:
        The text without those trailing bytes.
    """
    var bytes = text.as_bytes()
    var end = len(bytes)
    while end > 0 and (
        bytes[end - 1] == 10 or bytes[end - 1] == 32 or bytes[end - 1] == 9
    ):
        end -= 1
    return String(text[byte=:end])


def test_environment_wrapper_returns_infinity_or_the_checked_bound() raises:
    """The wrapper consults the environment check and then the checked bound."""
    var text = Path("extensions/carla/curve_sum2.mojo").read_text()
    var wrapper = _trim_end(_function(text, "_sum2_error"))
    var expected = _trim_end(
        "def _sum2_error(magnitude: Float64, inherited: Float64, count: Int)"
        + " -> Float64:\n    if not _sum2_supported_environment():\n"
        + "        return inf[DType.float64]()\n"
        + "    return _sum2_error_checked(magnitude, inherited, count)\n"
    )
    assert_equal(wrapper, expected)
    assert_equal(_calls(wrapper, "_sum2_supported_environment"), 1)
    assert_equal(_calls(wrapper, "_sum2_error_checked"), 1)


def test_upper_accumulation_preserves_signed_zero_contract() raises:
    """Point addition matches the outward high endpoint, including both zeros.
    """
    var samples = List[Float64]()
    samples.append(0.0)
    samples.append(_float(UInt64(1) << 63))
    samples.append(_float(1))
    samples.append(1.0)
    samples.append(inf[DType.float64]())
    for one_index in range(len(samples)):
        var one = samples[one_index]
        for two_index in range(len(samples)):
            var two = samples[two_index]
            var actual = _sum2_reference_add_upper(one, two)
            assert_equal(_bits(actual), _bits(_endpoint_add_high(one, two)))


def test_native_reference_has_no_production_sum2_dependency() raises:
    """The reference file names no production Sum2 helper."""
    var text = Path("tests/_spiral_sum2_reference.mojo").read_text()
    var lines = text.split("\n")
    for part in lines:
        var line = String(part)
        assert_true(not _forbidden_module(_module_name(line)))
    assert_true(not _has_name(text, "_sum2_error"))
    assert_true(not _has_name(text, "_sum2_update"))
    var error = _body(_function(text, "_sum2_reference_error"))
    assert_true(not _has_name(error, "_Interval"))
    var names = _invocations(error)
    names.extend(
        _invocations(_body(_function(text, "_sum2_reference_successor")))
    )
    names.extend(
        _invocations(_body(_function(text, "_sum2_reference_add_upper")))
    )
    for name in names:
        assert_true(_reference_call(name), name)
    var production = Path("extensions/carla/curve_sum2.mojo").read_text()
    var checked = _invocations(
        _body(_function(production, "_sum2_error_checked"))
    )
    for name in checked:
        assert_true(_production_call(name), name)
    var spiral = _function(text, "_sum2_reference_spiral")
    assert_equal(_calls(spiral, "_reference_half"), 5)
    assert_equal(_calls(spiral, "_sum2_reference_error"), 2)
    assert_equal(_calls(spiral, "_sum2_reference_add_upper"), 4)


def main() raises:
    TestSuite.discover_tests[__functions_in_module()]().run()
