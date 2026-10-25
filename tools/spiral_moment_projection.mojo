# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the stored-half helper used by the ideal spiral projection.

The helper starts with one half product. Later statements may read that
result, return it, or write its error. They must not redefine it.
"""

from tools.spiral_moment_graph import normalized_block


def _fail(message: String) raises:
    """Raise a projection error.

    Args:
        message: The failure text.

    Raises:
        Error: The helper check failed.
    """
    raise Error("spiral moment projection: " + message)


def _collapse(text: String) -> String:
    """Return `text` with ASCII whitespace removed.

    Args:
        text: A signature fragment.

    Returns:
        The same characters without spaces, tabs, or newlines.
    """
    var out = String()
    for byte in text.as_bytes():
        if byte == 32 or byte == 9 or byte == 10 or byte == 13:
            continue
        out += chr(Int(byte))
    return out


def _spaces(text: String) -> String:
    """Return `text` with ASCII whitespace runs folded to one space.

    Args:
        text: One statement.

    Returns:
        The statement with single spaces.
    """
    var out = String()
    var pending = False
    for byte in text.as_bytes():
        var space = byte == 32 or byte == 9 or byte == 10 or byte == 13
        if space:
            pending = out.byte_length() > 0
            continue
        if pending:
            out += " "
            pending = False
        out += chr(Int(byte))
    return out


def _is_name_byte(byte: UInt8, first: Bool) -> Bool:
    """Return whether `byte` can appear in an identifier.

    Args:
        byte: One source byte.
        first: True for the first byte of the identifier.

    Returns:
        True for an ASCII letter or underscore, and a digit after that.
    """
    if (
        (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    ):
        return True
    if not first and byte >= 48 and byte <= 57:
        return True
    return False


def _skip_signature(text: String) raises -> Int:
    """Return the byte index of the helper body.

    Args:
        text: The normalized helper.

    Returns:
        The first byte after the signature colon.

    Raises:
        Error: The declaration is not the reviewed generic helper.
    """
    var raw = text.as_bytes()
    var index = 0
    while index < len(raw) and (raw[index] == 32 or raw[index] == 10):
        index += 1
    if index < len(raw) and raw[index] == 64:
        _fail("unsupported ideal function declaration")
    var marker = "def _stored_half["
    if index + marker.byte_length() > len(raw):
        _fail("unsupported ideal function declaration")
    var head = text[byte = index : index + marker.byte_length()]
    if String(head) != marker:
        _fail("unsupported ideal function declaration")
    index += marker.byte_length()
    var generic_start = index
    var depth = 1
    while index < len(raw) and depth > 0:
        if raw[index] == 91:
            depth += 1
        elif raw[index] == 93:
            depth -= 1
        index += 1
    if depth != 0:
        _fail("unsupported ideal function declaration")
    var generic = text[byte = generic_start : index - 1]
    if _collapse(String(generic)) != "derivatives:Bool":
        _fail("changed ideal generic declaration")
    if index >= len(raw) or raw[index] != 40:
        _fail("ideal helper declaration or decorator changed")
    index += 1
    var param_start = index
    depth = 1
    while index < len(raw) and depth > 0:
        if raw[index] == 40:
            depth += 1
        elif raw[index] == 41:
            depth -= 1
        index += 1
    if depth != 0:
        _fail("ideal helper declaration or decorator changed")
    var params = _collapse(String(text[byte = param_start : index - 1]))
    var param_text = String()
    var param_bytes = params.as_bytes()
    var param_end = len(param_bytes)
    if param_end > 0 and param_bytes[param_end - 1] == 44:
        param_end -= 1
    var param_index = 0
    while param_index < param_end:
        param_text += chr(Int(param_bytes[param_index]))
        param_index += 1
    if param_text != "value:_JetExpression[derivatives]":
        _fail("ideal helper declaration or decorator changed")
    while index < len(raw) and (raw[index] == 32 or raw[index] == 10):
        index += 1
    var arrow = text[byte = index : index + 2]
    if String(arrow) != "->":
        _fail("ideal helper declaration or decorator changed")
    index += 2
    var type_start = index
    while index < len(raw) and raw[index] != 58:
        index += 1
    if index >= len(raw):
        _fail("ideal helper declaration or decorator changed")
    var returned = _collapse(String(text[byte=type_start:index]))
    if returned != "_JetExpression[derivatives]":
        _fail("ideal helper declaration or decorator changed")
    return index + 1


def _first_statement(text: String, start: Int) raises -> Int:
    """Require the helper's first statement to be the half product.

    Args:
        text: The normalized helper.
        start: The first body byte.

    Returns:
        The byte after that statement.

    Raises:
        Error: The initial expression changed.
    """
    var raw = text.as_bytes()
    var index = start
    while index < len(raw) and (
        raw[index] == 32 or raw[index] == 9 or raw[index] == 10
    ):
        index += 1
    var depth = 0
    var begin = index
    while index < len(raw):
        if raw[index] == 40 or raw[index] == 91:
            depth += 1
        elif raw[index] == 41 or raw[index] == 93:
            depth -= 1
        if raw[index] == 10 and depth == 0:
            break
        index += 1
    var statement = _spaces(String(text[byte=begin:index]))
    var spelled = String()
    var statement_bytes = statement.as_bytes()
    var statement_index = 0
    if statement.startswith("var "):
        statement_index = 4
    while statement_index < len(statement_bytes):
        spelled += chr(Int(statement_bytes[statement_index]))
        statement_index += 1
    if spelled != "result = value * _JetExpression[derivatives].constant(0.5)":
        _fail("ideal helper initial expression changed")
    if index < len(raw) and raw[index] == 10:
        index += 1
    return index


def _call_paren(tokens: List[String], index: Int) -> Bool:
    """Return whether the parenthesis at `index` opens a call.

    Args:
        tokens: The body tokens.
        index: The `(` token.

    Returns:
        True when a name or a closing bracket precedes the parenthesis.
    """
    if index == 0:
        return False
    var previous = tokens[index - 1]
    if previous == ")" or previous == "]":
        return True
    if previous.byte_length() == 0:
        return False
    var byte = previous.as_bytes()[0]
    return _is_name_byte(byte, True)


def _check_uses(text: String) raises:
    """Refuse an unapproved use of the helper result.

    Args:
        text: The helper body after the initial statement.

    Raises:
        Error: A return, field, rebinding, call, or other result use changed.
    """
    var raw = text.as_bytes()
    var tokens = List[String]()
    var index = 0
    while index < len(raw):
        var byte = raw[index]
        if byte == 32 or byte == 9 or byte == 10 or byte == 13:
            index += 1
            continue
        if _is_name_byte(byte, True):
            var end = index + 1
            while end < len(raw) and _is_name_byte(raw[end], False):
                end += 1
            tokens.append(String(text[byte=index:end]))
            index = end
            continue
        if (
            byte == 46
            and index + 1 < len(raw)
            and raw[index + 1] >= 48
            and raw[index + 1] <= 57
        ):
            var end = index + 1
            while end < len(raw) and raw[end] >= 48 and raw[end] <= 57:
                end += 1
            tokens.append(String(text[byte=index:end]))
            index = end
            continue
        tokens.append(String(chr(Int(byte))))
        index += 1
    var calls = List[Bool]()
    index = 0
    while index < len(tokens):
        var token = tokens[index]
        if token == "(":
            calls.append(_call_paren(tokens, index))
        elif token == ")" and len(calls) > 0:
            _ = calls.pop()
        elif token == "return":
            var returned = String()
            if index + 1 < len(tokens):
                returned = tokens[index + 1]
            var after_return = String()
            if index + 2 < len(tokens):
                after_return = tokens[index + 2]
            if (
                returned != "result"
                or after_return == "."
                or after_return == "("
            ):
                _fail("ideal helper return changed")
        elif token == "result":
            var nxt = String()
            if index + 1 < len(tokens):
                nxt = tokens[index + 1]
            var prev = String()
            if index > 0:
                prev = tokens[index - 1]
            if prev == "return":
                if nxt == "." or nxt == "(":
                    _fail("ideal helper return changed")
            elif nxt == "=" or nxt == "+=" or nxt == "-=":
                _fail("ideal helper result rebound")
            elif nxt == ".":
                var attr = String()
                if index + 2 < len(tokens):
                    attr = tokens[index + 2]
                var after = String()
                if index + 3 < len(tokens):
                    after = tokens[index + 3]
                if after == "=" and attr != "error":
                    _fail("non-error result field changed")
                if not (after == "=" and attr == "error"):
                    _fail("unapproved ideal helper result use")
            elif (
                len(calls) > 0
                and calls[len(calls) - 1]
                and (prev == "(" or prev == ",")
            ):
                _fail("ideal helper result escapes")
            else:
                _fail("unapproved ideal helper result use")
        index += 1


def stored_half_projection(helper: String) raises:
    """Require the reviewed stored-half helper shape.

    Args:
        helper: The source from `def _stored_half[`.

    Raises:
        Error: The declaration, the half product, or a result use changed.
    """
    var text = normalized_block(helper)
    var body = _skip_signature(text)
    var rest = _first_statement(text, body)
    _check_uses(String(text[byte=rest:]))
