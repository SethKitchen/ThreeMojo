# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the stored jet aliases and derivative-field gate.

`_Jet` binds the derivative jet. `_ValueJet` binds the value jet. The
stored helpers do not read `first`, `second`, or `derivatives`.
"""

from tests._python_tokens import _tokenize


comptime _NAME = 1
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55


def _fail(message: String) raises:
    """Raise a jet-gate error.

    Args:
        message: The failure text.

    Raises:
        Error: The gate check failed.
    """
    raise Error("sampled jet gate: " + message)


def _bad() raises:
    """Raise a syntax error for the jet module.

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


def _opens(kind: Int, text: String) -> Bool:
    """Return whether the token opens a bracket.

    Args:
        kind: The token kind.
        text: The token text.

    Returns:
        True for `(`, `[`, or `{`.
    """
    if kind != _OP:
        return False
    if text == "(":
        return True
    if text == "[":
        return True
    return text == "{"


def _closes(kind: Int, text: String) -> Bool:
    """Return whether the token closes a bracket.

    Args:
        kind: The token kind.
        text: The token text.

    Returns:
        True for `)`, `]`, or `}`.
    """
    if kind != _OP:
        return False
    if text == ")":
        return True
    if text == "]":
        return True
    return text == "}"


def _statements(kinds: List[Int], texts: List[String]) -> List[List[String]]:
    """Return the depth-zero statements.

    Args:
        kinds: The token kinds.
        texts: The token texts.

    Returns:
        Each top-level statement, without newlines.
    """
    var depth = 0
    var bracket = 0
    var current = List[String]()
    var rows = List[List[String]]()
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        elif depth == 0:
            if kind == _NEWLINE and bracket == 0:
                if len(current) > 0:
                    rows.append(current^)
                    current = List[String]()
            else:
                if _opens(kind, texts[index]):
                    bracket += 1
                elif _closes(kind, texts[index]):
                    bracket -= 1
                current.append(texts[index])
        index += 1
    if len(current) > 0:
        rows.append(current^)
    return rows^


def _alias(rows: List[List[String]], name: String, flag: String) raises:
    """Require one alias from `name` to `_JetExpression[flag]`.

    Args:
        rows: The top-level statements.
        name: `_Jet` or `_ValueJet`.
        flag: `True` or `False`.

    Raises:
        Error: The alias is missing, repeated, or changed.
    """
    var count = 0
    var exact = False
    var index = 0
    while index < len(rows):
        var words = rows[index].copy()
        var cursor = 0
        if len(words) > 0 and words[0] == "comptime":
            cursor = 1
        if cursor < len(words) and words[cursor] == name:
            count += 1
            var matched = len(words) == cursor + 6
            if matched:
                matched = words[cursor + 1] == "="
            if matched:
                matched = words[cursor + 2] == "_JetExpression"
            if matched:
                matched = words[cursor + 3] == "["
            if matched:
                matched = words[cursor + 4] == flag
            if matched:
                matched = words[cursor + 5] == "]"
            exact = matched
        index += 1
    if count != 1:
        _fail("missing or ambiguous actual alias: " + name)
    if not exact:
        _fail("actual derivative alias changed: " + name)


def _span(
    kinds: List[Int], texts: List[String], name: String
) raises -> Tuple[Int, Int]:
    """Return the body span of top-level `name`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        name: The function name.

    Returns:
        The first body token and the token after the body.

    Raises:
        Error: The function is missing, repeated, or has no body.
    """
    var depth = 0
    var fresh = True
    var found = 0
    var name_at = -1
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
                    found += 1
                    name_at = index + 1
            fresh = False
        index += 1
    if found != 1:
        _fail("missing or ambiguous function: " + name)
    var cursor = name_at + 1
    if cursor < len(kinds) and _opens(kinds[cursor], texts[cursor]):
        var brackets = 1
        cursor += 1
        while cursor < len(kinds) and brackets > 0:
            if _opens(kinds[cursor], texts[cursor]):
                brackets += 1
            elif _closes(kinds[cursor], texts[cursor]):
                brackets -= 1
            cursor += 1
    var signature = 0
    var colon = -1
    while cursor < len(kinds):
        if _opens(kinds[cursor], texts[cursor]):
            signature += 1
        elif _closes(kinds[cursor], texts[cursor]):
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
    var body = cursor + 1
    var indent = 1
    cursor = body
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
    return (body, stop)


def _fields(kinds: List[Int], texts: List[String], name: String) raises:
    """Refuse a derivative attribute in `name`.

    Args:
        kinds: The token kinds.
        texts: The token texts.
        name: The stored helper.

    Raises:
        Error: The helper reads `first`, `second`, or `derivatives`.
    """
    var span = _span(kinds, texts, name)
    var index = span[0]
    while index + 1 < span[1]:
        if kinds[index] == _OP and texts[index] == ".":
            var field = texts[index + 1]
            if field == "first":
                _fail("derivative-field/flag read in stored helper: " + name)
            if field == "second":
                _fail("derivative-field/flag read in stored helper: " + name)
            if field == "derivatives":
                _fail("derivative-field/flag read in stored helper: " + name)
        index += 1


def stored_helper_fields(source: String) raises:
    """Require the stored helpers to avoid derivative reads.

    Args:
        source: The `curve_interval` module.

    Raises:
        Error: A helper is missing or reads a derivative field.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _load(source, kinds, texts)
    _fields(kinds, texts, "_without_derivatives")
    _fields(kinds, texts, "_stored_difference")
    _fields(kinds, texts, "_stored_blend_error")
    _fields(kinds, texts, "_stored_half")


def stored_jet_gate(source: String) raises:
    """Require the stored jet aliases and the derivative-field gate.

    Args:
        source: The `curve_interval` module.

    Raises:
        Error: An alias changed, a helper is missing, or a helper reads
        a derivative field.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _load(source, kinds, texts)
    var rows = _statements(kinds, texts)
    _alias(rows, "_Jet", "True")
    _alias(rows, "_ValueJet", "False")
    _fields(kinds, texts, "_without_derivatives")
    _fields(kinds, texts, "_stored_difference")
    _fields(kinds, texts, "_stored_blend_error")
    _fields(kinds, texts, "_stored_half")
