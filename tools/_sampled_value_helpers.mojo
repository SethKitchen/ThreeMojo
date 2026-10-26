# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the sampled value helper set.

Seventeen helpers stay at the top level. The uncertain value, the sampled
bound, and the lane bound keep their reviewed bodies.
"""

from tests._python_tokens import _tokenize


comptime _NAME = 1
comptime _STRING = 3
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55


def _fail(message: String) raises:
    """Raise a sampled-helper error.

    Args:
        message: The failure text.

    Raises:
        Error: The helper check failed.
    """
    raise Error("sampled value helper: " + message)


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


def _dropped(kind: Int, text: String) -> Bool:
    """Return whether normalization drops the token.

    Args:
        kind: The token kind.
        text: The token text.

    Returns:
        True for layout tokens and Mojo keywords Python strips.
    """
    if kind == _NEWLINE or kind == _INDENT or kind == _DEDENT:
        return True
    if kind != _NAME:
        return False
    if text == "var":
        return True
    if text == "mut":
        return True
    if text == "out":
        return True
    if text == "ref":
        return True
    if text == "comptime":
        return True
    return text == "raises"


def _normalize(
    kinds: List[Int], texts: List[String], start: Int, end: Int
) -> String:
    """Return the comparable text of one token span.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        start: The first token.
        end: The token after the span.

    Returns:
        The tokens, separated by spaces, without layout or trailing commas.
    """
    var kept_texts = List[String]()
    var index = start
    while index < end:
        if not _dropped(kinds[index], texts[index]):
            kept_texts.append(texts[index])
        index += 1
    var out = String("")
    var saw = False
    index = 0
    while index < len(kept_texts):
        var skip = False
        if kept_texts[index] == "," and index + 1 < len(kept_texts):
            var nxt = kept_texts[index + 1]
            if nxt == ")" or nxt == "]":
                skip = True
        if not skip:
            if saw:
                out += " "
            out += kept_texts[index]
            saw = True
        index += 1
    return out


def _names() -> List[String]:
    """Return the reviewed helper names.

    Returns:
        The seventeen top-level function names.
    """
    var names = List[String]()
    names.append("_uncertain_value")
    names.append("_atan_value_branch")
    names.append("_atan_value")
    names.append("_atan2_value")
    names.append("_polynomial_value")
    names.append("_unknown_value_point")
    names.append("_value_geometry_distance")
    names.append("_sample_blend_value")
    names.append("_sample_value")
    names.append("_reference_sampled_value")
    names.append("_union_value_points")
    names.append("_sinc_value")
    names.append("_constant_sincos_value")
    names.append("_arc_offset_value")
    names.append("_sampled_lane_value_bound")
    names.append("_lane_value_bound")
    names.append("_lane_value_bound_impl")
    return names^


def _surface(kinds: List[Int], texts: List[String]) raises:
    """Require imports, strings, and the reviewed helpers only.

    Args:
        kinds: The token kinds.
        texts: The token texts.

    Raises:
        Error: A top-level statement is executable, or a helper is missing
        or repeated.
    """
    var depth = 0
    var bracket = 0
    var kinds_row = List[Int]()
    var texts_row = List[String]()
    var defs = List[String]()
    var index = 0
    while index <= len(kinds):
        var finish = index == len(kinds)
        var kind = 0
        var text = String("")
        if not finish:
            kind = kinds[index]
            text = texts[index]
        var boundary = finish or (
            depth == 0 and kind == _NEWLINE and bracket == 0
        )
        if boundary and len(texts_row) > 0:
            if texts_row[0] == "def" and len(texts_row) > 1:
                defs.append(texts_row[1])
            elif texts_row[0] == "from":
                pass
            elif len(texts_row) == 1 and kinds_row[0] == _STRING:
                pass
            else:
                _fail("unexpected top-level execution in sampled graph")
            kinds_row = List[Int]()
            texts_row = List[String]()
        if (
            not finish
            and depth == 0
            and kind != _INDENT
            and kind != _DEDENT
            and kind != _NEWLINE
        ):
            if kind == _OP and _opens(text):
                bracket += 1
            elif kind == _OP and _closes(text):
                bracket -= 1
            kinds_row.append(kind)
            texts_row.append(text)
        if not finish:
            if kind == _INDENT:
                depth += 1
            elif kind == _DEDENT:
                depth -= 1
        index += 1
    var expected = _names()
    if len(defs) != len(expected):
        _fail("missing or extra sampled helper")
    var cursor = 0
    while cursor < len(expected):
        var count = 0
        var item = 0
        while item < len(defs):
            if defs[item] == expected[cursor]:
                count += 1
            item += 1
        if count != 1:
            _fail("missing or extra sampled helper")
        cursor += 1


def _span(
    kinds: List[Int], texts: List[String], name: String
) raises -> Tuple[Int, Int]:
    """Return the token span of top-level `name`, including `def`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        name: The function name.

    Returns:
        The `def` token and the token after the body.

    Raises:
        Error: The function is missing or has no body.
    """
    var depth = 0
    var fresh = True
    var found = -1
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
            fresh = True
        elif kind == _DEDENT:
            depth -= 1
            fresh = True
        elif kind == _NEWLINE:
            if depth == 0:
                fresh = True
        else:
            if depth == 0 and fresh and texts[index] == "def":
                if index + 1 < len(kinds) and texts[index + 1] == name:
                    found = index
            fresh = False
        index += 1
    if found < 0:
        _fail("sampled helper diverged: " + name)
    var cursor = found + 2
    if cursor < len(kinds) and _opens(texts[cursor]):
        var brackets = 1
        cursor += 1
        while cursor < len(kinds) and brackets > 0:
            if _opens(texts[cursor]):
                brackets += 1
            elif _closes(texts[cursor]):
                brackets -= 1
            cursor += 1
    var signature = 0
    var colon = -1
    while cursor < len(kinds):
        if _opens(texts[cursor]):
            signature += 1
        elif _closes(texts[cursor]):
            signature -= 1
        elif kinds[cursor] == _OP and texts[cursor] == ":" and signature == 0:
            colon = cursor
            break
        cursor += 1
    if colon < 0:
        _fail("unsupported ideal source syntax")
    cursor = colon + 1
    while cursor < len(kinds) and kinds[cursor] == _NEWLINE:
        cursor += 1
    if cursor >= len(kinds) or kinds[cursor] != _INDENT:
        _fail("unsupported ideal source syntax")
    var indent = 1
    cursor += 1
    var stop = len(kinds)
    while cursor < len(kinds):
        if kinds[cursor] == _INDENT:
            indent += 1
        elif kinds[cursor] == _DEDENT:
            indent -= 1
            if indent == 0:
                stop = cursor
                break
        cursor += 1
    return (found, stop)


def _match(
    kinds: List[Int], texts: List[String], name: String, source: String
) raises:
    """Require `name` to match `source`.

    Args:
        kinds: The module token kinds.
        texts: The module token texts.
        name: The helper name.
        source: The reviewed helper source.

    Raises:
        Error: The helper diverged.
    """
    var span = _span(kinds, texts, name)
    var actual = _normalize(kinds, texts, span[0], span[1])
    var ekinds = List[Int]()
    var etexts = List[String]()
    _load(source, ekinds, etexts)
    var expected = _normalize(ekinds, etexts, 0, len(ekinds))
    if actual != expected:
        _fail("sampled helper diverged: " + name)


def sampled_value_helpers(source: String) raises:
    """Require the reviewed sampled helper set and three helper bodies.

    Args:
        source: The `lane_value_bounds` module.

    Raises:
        Error: A helper is missing, an extra top-level statement appears,
        or a reviewed body changed.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _load(source, kinds, texts)
    _surface(kinds, texts)
    _match(
        kinds,
        texts,
        "_uncertain_value",
        (
            "def _uncertain_value(value: _Interval) -> _ValueJet:\n    return"
            " _uncertain_expression[False](value)\n"
        ),
    )
    _match(
        kinds,
        texts,
        "_sampled_lane_value_bound",
        (
            "def _sampled_lane_value_bound(road: Road, section: Int, lane: Int,"
            " low: Float64, high: Float64) raises -> Tuple[_ValueJet,"
            " _ValueJet, _ValueJet]:\n    return"
            " _lane_value_bound_impl[False](road, section, lane, low, high)\n"
        ),
    )
    _match(
        kinds,
        texts,
        "_lane_value_bound",
        (
            "def _lane_value_bound(road: Road, section: Int, lane: Int, low:"
            " Float64, high: Float64) raises -> Tuple[_ValueJet, _ValueJet,"
            " _ValueJet]:\n    var at = info_index(road.info.geometries, low)\n"
            "    if at >= 0 and road.info.geometries[at].geometry.kind =="
            " SPIRAL:\n        var full = _lane_jet(road, section, lane, low,"
            " high)\n        return (_without_derivatives(full[0]),"
            " _without_derivatives(full[1]), _without_derivatives(full[2]))\n  "
            "  return _lane_value_bound_impl[True](road, section, lane, low,"
            " high)\n"
        ),
    )
