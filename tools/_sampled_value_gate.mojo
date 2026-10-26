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
