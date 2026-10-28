# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the sampled value imports and the value-only field gate.

Eight imports match the historical pin. The road-info import is the
reviewed alias. The value graph does not read a derivative or `sqrt`.
"""

from tests._python_tokens import _tokenize


comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55
comptime _NAME = 1


def _fail(message: String) raises:
    """Raise a sampled-value gate error.

    Args:
        message: The failure text.

    Raises:
        Error: The gate check failed.
    """
    raise Error("sampled value gate: " + message)


def _bad() raises:
    """Raise a syntax error for the value module.

    Raises:
        Error: The source cannot be tokenized.
    """
    _fail("unsupported ideal source syntax")


def _load(source: String, mut kinds: List[Int], mut texts: List[String]) raises:
    """Tokenize `source`.

    Args:
        source: Module source.
        kinds: The token kinds, replaced by this call.
        texts: The token texts, replaced by this call.

    Raises:
        Error: The source cannot be tokenized.
    """
    var failed = False
    try:
        _tokenize(source, kinds, texts)
    except error:
        failed = True
    if failed:
        _bad()


def _opens(text: String) -> Bool:
    """Return whether `text` opens a bracket.

    Args:
        text: The token text.

    Returns:
        True for `(`, `[`, or `{`.
    """
    if text == "(":
        return True
    if text == "[":
        return True
    return text == "{"


def _closes(text: String) -> Bool:
    """Return whether `text` closes a bracket.

    Args:
        text: The token text.

    Returns:
        True for `)`, `]`, or `}`.
    """
    if text == ")":
        return True
    if text == "]":
        return True
    return text == "}"


def _imports(kinds: List[Int], texts: List[String]) -> List[String]:
    """Return the top-level `from` imports.

    Args:
        kinds: The token kinds.
        texts: The token texts.

    Returns:
        Each import, with tokens separated by spaces.
    """
    var depth = 0
    var bracket = 0
    var current = List[String]()
    var rows = List[String]()
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        var text = texts[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        elif depth == 0:
            if kind == _NEWLINE and bracket == 0:
                if len(current) > 0 and current[0] == "from":
                    var line = String("")
                    var cursor = 0
                    while cursor < len(current):
                        if cursor > 0:
                            line += " "
                        line += current[cursor]
                        cursor += 1
                    rows.append(line)
                current = List[String]()
            else:
                if kind == _OP and _opens(text):
                    bracket += 1
                elif kind == _OP and _closes(text):
                    bracket -= 1
                current.append(text)
        index += 1
    if len(current) > 0 and current[0] == "from":
        var line = String("")
        var cursor = 0
        while cursor < len(current):
            if cursor > 0:
                line += " "
            line += current[cursor]
            cursor += 1
        rows.append(line)
    return rows^


def _expected() -> List[String]:
    """Return the reviewed import list.

    Returns:
        The nine imports, in source order.
    """
    var rows = List[String]()
    rows.append(
        "from extensions . carla . curve_interval import ( _stored_difference ,"
        " _stored_half , _stored_blend_error , _Interval , _ValueJet ,"
        " _without_derivatives , )"
    )
    rows.append(
        "from extensions . carla . curve_bounds import ( _sample_index ,"
        " _intersect_ideal_bounds , _lane_jet , )"
    )
    rows.append(
        "from extensions . carla . curve_trig import ( _expression_polynomial ,"
        " _uncertain_expression , _sincos_expression , _PI , _HALF_PI ,"
        " _QUARTER_PI , _ATAN_REDUCE , _ATAN_COEFFICIENTS , _SIN_COEFFICIENTS ,"
        " _PHASE_LIMIT , _sign_bit , _curve_cos , _curve_sin , _curve_atan2 , )"
    )
    rows.append(
        "from extensions . carla . geometry import ( RoadGeometry , PARAM_POLY3"
        " , POLY3 , LINE , ARC , SPIRAL , )"
    )
    rows.append("from std . math import isfinite")
    rows.append("from extensions . carla . polynomial import CubicPolynomial")
    rows.append("from extensions . carla . road import Road")
    rows.append(
        "from extensions . carla . road_info import _info_index_si as"
        " info_index"
    )
    rows.append("from math . vector3 import Vector3")
    return rows^


def _same(actual: List[String], expected: List[String]) -> Bool:
    """Return whether the import lists match.

    Args:
        actual: The imports in the module.
        expected: The reviewed imports.

    Returns:
        True when the lists have the same texts in the same order.
    """
    if len(actual) != len(expected):
        return False
    var index = 0
    while index < len(actual):
        if actual[index] != expected[index]:
            return False
        index += 1
    return True


def _fields(kinds: List[Int], texts: List[String]) raises:
    """Refuse a derivative or square-root attribute.

    Args:
        kinds: The token kinds.
        texts: The token texts.

    Raises:
        Error: The value graph reads `first`, `second`, `derivatives`,
        or `sqrt`.
    """
    var index = 0
    while index + 1 < len(kinds):
        if (
            kinds[index] == _OP
            and texts[index] == "."
            and kinds[index + 1] == _NAME
        ):
            var field = texts[index + 1]
            if field == "first":
                _fail("derivative-field/flag read or sqrt in value-only graph")
            if field == "second":
                _fail("derivative-field/flag read or sqrt in value-only graph")
            if field == "derivatives":
                _fail("derivative-field/flag read or sqrt in value-only graph")
            if field == "sqrt":
                _fail("derivative-field/flag read or sqrt in value-only graph")
        index += 1


def sampled_value_gate(source: String) raises:
    """Require the reviewed sampled-value imports and field gate.

    Args:
        source: The `lane_value_bounds` module.

    Raises:
        Error: An import changed, or the value graph reads a derivative
        or `sqrt`.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _load(source, kinds, texts)
    if not _same(_imports(kinds, texts), _expected()):
        _fail("sampled graph imports changed")
    _fields(kinds, texts)


def _ident_start(byte: UInt8) -> Bool:
    """Return whether `byte` can start a Python name."""
    return (
        byte == 95
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
    )


def _ident_continue(byte: UInt8) -> Bool:
    """Return whether `byte` can continue a Python name."""
    return _ident_start(byte) or (byte >= 48 and byte <= 57)


def _renamed(name: String) -> String:
    """Return the value-only spelling of `name`, or empty."""
    if name == "_polynomial_jet":
        return "_polynomial_value"
    if name == "_unknown_point":
        return "_unknown_value_point"
    if name == "_geometry_distance":
        return "_value_geometry_distance"
    if name == "_sample_blend_jet":
        return "_sample_blend_value"
    if name == "_sample_jet":
        return "_sample_value"
    if name == "_atan_branch":
        return "_atan_value_branch"
    if name == "_atan_jet":
        return "_atan_value"
    if name == "_atan2_jet":
        return "_atan2_value"
    if name == "_jet_polynomial":
        return "_expression_polynomial"
    if name == "_uncertain":
        return "_uncertain_value"
    if name == "_Jet":
        return "_ValueJet"
    if name == "_sinc_jet":
        return "_sinc_value"
    if name == "_sincos_jet":
        return "_sincos_expression"
    if name == "_arc_offset_jet":
        return "_arc_offset_value"
    if name == "_constant_sincos_jet":
        return "_constant_sincos_value"
    if name == "_union_points":
        return "_union_value_points"
    return ""


def sampled_identifier(name: String) -> String:
    """Return the value-only spelling of one identifier.

    Args:
        name: A Python name token.

    Returns:
        The renamed spelling, or `name` when the checker keeps it.
    """
    var renamed = _renamed(name)
    if renamed == "":
        return name
    return renamed


def _string_prefix(name: String) -> Bool:
    """Return whether `name` is a Python string prefix."""
    if name == "r" or name == "R" or name == "b" or name == "B":
        return True
    if name == "f" or name == "F" or name == "u" or name == "U":
        return True
    if name == "rf" or name == "rF" or name == "Rf" or name == "RF":
        return True
    if name == "fr" or name == "fR" or name == "Fr" or name == "FR":
        return True
    if name == "rb" or name == "rB" or name == "Rb" or name == "RB":
        return True
    if name == "br" or name == "bR" or name == "Br" or name == "BR":
        return True
    return False


def _has_f(name: String) -> Bool:
    """Return whether a string prefix formats expressions."""
    var raw = name.as_bytes()
    for index in range(len(raw)):
        if raw[index] == 102 or raw[index] == 70:
            return True
    return False


def _append_slice(mut out: String, text: String, start: Int, end: Int):
    """Append `text[start:end]` to `out`."""
    out += String(text[byte=start:end])


def rename_sampled_identifiers(text: String) -> String:
    """Rename jet identifiers the way `check_sampled_values.translated` does.

    Names inside comments and ordinary strings stay. A formatted string
    renames names in its expressions. The spelling is the value-only name.

    Args:
        text: Source text.

    Returns:
        The text with those names replaced.
    """
    var raw = text.as_bytes()
    var count = len(raw)
    var out = String()
    var index = 0
    while index < count:
        var byte = raw[index]
        if byte == 35:
            var end = index
            while end < count and raw[end] != 10:
                end += 1
            _append_slice(out, text, index, end)
            index = end
            continue
        if _ident_start(byte):
            var end = index + 1
            while end < count and _ident_continue(raw[end]):
                end += 1
            var name = String(text[byte=index:end])
            if (
                end < count
                and (raw[end] == 34 or raw[end] == 39)
                and _string_prefix(name)
            ):
                _append_slice(out, text, index, end)
                index = _copy_string(
                    out, text, end, raw[end], _has_f(name), _is_raw(name)
                )
                continue
            var replacement = _renamed(name)
            if replacement.byte_length() == 0:
                out += name
            else:
                out += replacement
            index = end
            continue
        if byte == 34 or byte == 39:
            index = _copy_string(out, text, index, byte, False, False)
            continue
        out += String(text[byte = index : index + 1])
        index += 1
    return out


def _is_raw(name: String) -> Bool:
    """Return whether a string prefix is raw."""
    var raw = name.as_bytes()
    for index in range(len(raw)):
        if raw[index] == 114 or raw[index] == 82:
            return True
    return False


def _copy_string(
    mut out: String,
    text: String,
    start: Int,
    quote: UInt8,
    formatted: Bool,
    raw_string: Bool,
) -> Int:
    """Copy one string and return the index after it.

    Args:
        out: The renamed text.
        text: The source.
        start: The opening quote.
        quote: The quote byte.
        formatted: True when expressions inside braces are code.
        raw_string: True when backslashes are ordinary characters.

    Returns:
        The index of the first byte after the string.
    """
    var raw = text.as_bytes()
    var count = len(raw)
    var triple = (
        start + 2 < count
        and raw[start + 1] == quote
        and raw[start + 2] == quote
    )
    var mark = start
    var index = start + 1
    if triple:
        index = start + 3
    var depth = 0
    while index < count:
        if formatted and depth == 0 and raw[index] == 123:
            if index + 1 < count and raw[index + 1] == 123:
                index += 2
                continue
            _append_slice(out, text, mark, index + 1)
            depth = 1
            index += 1
            mark = index
            while index < count and depth > 0:
                if _ident_start(raw[index]):
                    var end = index + 1
                    while end < count and _ident_continue(raw[end]):
                        end += 1
                    _append_slice(out, text, mark, index)
                    var name = String(text[byte=index:end])
                    var replacement = _renamed(name)
                    if replacement.byte_length() == 0:
                        out += name
                    else:
                        out += replacement
                    index = end
                    mark = index
                    continue
                if raw[index] == 123:
                    depth += 1
                elif raw[index] == 125:
                    depth -= 1
                    if depth == 0:
                        _append_slice(out, text, mark, index)
                        mark = index
                        break
                index += 1
            continue
        if not raw_string and raw[index] == 92 and index + 1 < count:
            index += 2
            continue
        if raw[index] == quote:
            if not triple:
                _append_slice(out, text, mark, index + 1)
                return index + 1
            if (
                index + 2 < count
                and raw[index + 1] == quote
                and raw[index + 2] == quote
            ):
                _append_slice(out, text, mark, index + 3)
                return index + 3
        index += 1
    _append_slice(out, text, mark, count)
    return count


def extract_sampled_function(text: String, name: String) raises -> String:
    """Return one top-level function, as `check_sampled_values.function` does.

    Args:
        text: The module source.
        name: The function name, without a rename.

    Returns:
        The function text, through the line before the next `def` or decorator.

    Raises:
        Error: The function is missing or appears twice.
    """
    var needle = "def " + name
    var raw = text.as_bytes()
    var count = len(raw)
    var found = -1
    var open_end = -1
    var index = 0
    while index < count:
        var line = index == 0 or raw[index - 1] == 10
        if line and index + len(needle.as_bytes()) <= count:
            var word = String(
                text[byte = index : index + len(needle.as_bytes())]
            )
            if word == needle:
                var after = index + len(needle.as_bytes())
                if after < count and (raw[after] == 40 or raw[after] == 91):
                    if found >= 0:
                        raise Error("missing or ambiguous function: " + name)
                    found = index
                    open_end = after + 1
        index += 1
    if found < 0:
        raise Error("missing or ambiguous function: " + name)
    var cursor = open_end
    var stop = count
    while cursor < count:
        var line = raw[cursor - 1] == 10
        if line:
            if (
                cursor + 4 <= count
                and String(text[byte = cursor : cursor + 4]) == "def "
            ):
                stop = cursor
                break
            if raw[cursor] == 64:
                stop = cursor
                break
        cursor += 1
    return String(text[byte=found:stop])
