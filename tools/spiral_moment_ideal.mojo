# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Check the live ideal spiral statement layout.

The layout keeps the environment guard, the auxiliary declarations, the
loops, the stored-half calls, and the final error writes.
"""

from tools.spiral_moment_graph import normalized_block
from tools.spiral_moment_words import decimal_word


def _fail(message: String) raises:
    """Raise an ideal-layout error.

    Args:
        message: The failure text.

    Raises:
        Error: The layout check failed.
    """
    raise Error("spiral moment ideal: " + message)


def _signature_end(text: String) raises -> Int:
    """Return the byte after the function signature.

    Args:
        text: The normalized ideal spiral.

    Returns:
        The first byte of the function body.

    Raises:
        Error: The text is not the ideal spiral declaration.
    """
    var marker = "def _spiral_expression["
    if not text.startswith(marker):
        _fail("unsupported ideal function declaration")
    var raw = text.as_bytes()
    var depth = 0
    var index = 0
    while index < len(raw):
        var byte = raw[index]
        if byte == 40 or byte == 91 or byte == 123:
            depth += 1
        elif byte == 41 or byte == 93 or byte == 125:
            depth -= 1
            if depth < 0:
                _fail("unsupported ideal function declaration")
        if byte == 58 and depth == 0:
            return index + 1
        index += 1
    _fail("unsupported ideal function declaration")
    return 0


def _lines(text: String) -> List[String]:
    """Split `text` on newlines.

    Args:
        text: Source text.

    Returns:
        The lines, without newline characters.
    """
    var raw = text.as_bytes()
    var rows = List[String]()
    var start = 0
    var index = 0
    while index < len(raw):
        if raw[index] == 10:
            var piece = text[byte=start:index]
            rows.append(String(piece))
            start = index + 1
        index += 1
    if start < len(raw):
        var tail = text[byte=start:]
        rows.append(String(tail))
    return rows^


def _indent(line: String) -> Int:
    """Return the leading space count of `line`.

    Args:
        line: One source line.

    Returns:
        The number of leading spaces.
    """
    var raw = line.as_bytes()
    var count = 0
    while count < len(raw) and raw[count] == 32:
        count += 1
    return count


def _depth_after(line: String, depth: Int) raises -> Int:
    """Return the bracket depth after `line`.

    Args:
        line: One source line.
        depth: The depth before the line.

    Returns:
        The depth after the line.

    Raises:
        Error: A bracket closes too early.
    """
    var current = depth
    for byte in line.as_bytes():
        if byte == 40 or byte == 91 or byte == 123:
            current += 1
        elif byte == 41 or byte == 93 or byte == 125:
            current -= 1
            if current < 0:
                _fail("unsupported ideal function declaration")
    return current


def _statements(body: String) raises -> List[String]:
    """Return the ideal function's top-level statements.

    Args:
        body: The function body, including its leading newline.

    Returns:
        Each statement at the function's indent, with its nested lines.

    Raises:
        Error: The body is empty.
    """
    var rows = _lines(body)
    var statements = List[String]()
    var current = String()
    var depth = 0
    for row in rows:
        var start_depth = depth
        depth = _depth_after(row, depth)
        var stripped = row.lstrip(" ")
        if stripped.byte_length() == 0:
            continue
        if start_depth == 0 and _indent(row) == 4:
            if current.byte_length() > 0:
                statements.append(current)
            current = row
        elif current.byte_length() > 0:
            current += "\n" + row
    if current.byte_length() > 0:
        statements.append(current)
    return statements^


def _head(statement: String) -> String:
    """Return the first line of `statement` without indent.

    Args:
        statement: One statement.

    Returns:
        The first line, left-trimmed.
    """
    var newline = statement.find("\n")
    var line = statement
    if newline >= 0:
        var head = statement[byte=0:newline]
        line = String(head)
    return String(line.lstrip(" "))


def _stored_half_arguments(text: String) raises -> List[String]:
    """Return the names passed to `_stored_half`.

    Args:
        text: The ideal spiral.

    Returns:
        The argument names, in source order.

    Raises:
        Error: A call is not one name.
    """
    var marker = "_stored_half("
    var raw = text.as_bytes()
    var token = marker.as_bytes()
    var names = List[String]()
    var index = 0
    while index + len(token) <= len(raw):
        var same = True
        var offset = 0
        while offset < len(token):
            if raw[index + offset] != token[offset]:
                same = False
                break
            offset += 1
        if not same:
            index += 1
            continue
        var start = index + len(token)
        var end = start
        while end < len(raw) and raw[end] != 41:
            end += 1
        if end >= len(raw):
            _fail("expected exactly five reviewed stored-half calls")
        var raw_argument = String(text[byte=start:end])
        var argument = String(raw_argument.strip())
        names.append(argument^)
        index = end + 1
    return names^


def _require_head(statement: String, expected: String, message: String) raises:
    """Require the first line of `statement` to equal `expected`.

    Args:
        statement: One statement.
        expected: The reviewed first line.
        message: The failure text.

    Raises:
        Error: The first line differs.
    """
    if _head(statement) != expected:
        _fail(message)


def ideal_spiral_layout(text: String) raises:
    """Require the reviewed ideal spiral statement layout.

    Args:
        text: The ideal spiral source, or its normalized block.

    Raises:
        Error: The guard, declarations, loops, terms, or stored-half
        calls changed.
    """
    var source = normalized_block(text)
    var body_at = _signature_end(source)
    var body = source[byte=body_at:]
    var statements = _statements(String(body))
    if len(statements) != 19:
        _fail("Sum2 complete ideal statement layout changed")
    _require_head(
        statements[1],
        "if not _sum2_supported_environment():",
        "fresh Sum2 environment refusal changed or moved",
    )
    if statements[1].find("return (unknown, unknown, unknown)") < 0:
        _fail("fresh Sum2 environment refusal changed or moved")
    var declarations = List[String]()
    declarations.append("var x_magnitude = _Interval.point(0.0)")
    declarations.append("var y_magnitude = _Interval.point(0.0)")
    declarations.append("var x_inherited = _Interval.point(0.0)")
    declarations.append("var y_inherited = _Interval.point(0.0)")
    var index = 0
    while index < 4:
        if _head(statements[9 + index]) != declarations[index]:
            _fail("Sum2 declarations reordered or changed")
        index += 1
    _require_head(
        statements[14],
        "while piece < pieces:",
        "Sum2 complete ideal statement layout changed",
    )
    var loop = String(statements[14])
    if loop.find("while i < 5:") < 0:
        _fail("Sum2 complete outer-loop layout changed")
    if (
        loop.find(
            "_stored_half(step) * Expression.constant(weights[i]) * trig[1]"
        )
        < 0
        or loop.find(
            "_stored_half(step) * Expression.constant(weights[i]) * trig[0]"
        )
        < 0
    ):
        _fail("Sum2 immutable term definition moved or changed")
    if loop.find("x = x + term_x") < 0 or loop.find("y = y + term_y") < 0:
        _fail("Sum2 ideal term accumulation moved or changed")
    if (
        loop.find("x_magnitude = x_magnitude + _Interval.point(") < 0
        or loop.find("y_magnitude = y_magnitude + _Interval.point(") < 0
        or loop.find(
            "x_inherited = x_inherited + _Interval.point(term_x.error)"
        )
        < 0
        or loop.find(
            "y_inherited = y_inherited + _Interval.point(term_y.error)"
        )
        < 0
    ):
        _fail("Sum2 auxiliary updates reordered or changed")
    _require_head(
        statements[15],
        "x.error = _sum2_error_checked(",
        "Sum2 final error writes reordered or changed",
    )
    _require_head(
        statements[16],
        "y.error = _sum2_error_checked(",
        "Sum2 final error writes reordered or changed",
    )
    var names = _stored_half_arguments(source)
    var expected = List[String]()
    expected.append("step")
    expected.append("rate")
    expected.append("step")
    expected.append("step")
    expected.append("rate")
    if len(names) != len(expected):
        _fail("expected exactly five reviewed stored-half calls")
    index = 0
    while index < len(expected):
        if names[index] != expected[index]:
            _fail("expected exactly five reviewed stored-half calls")
        index += 1


def _name_char(byte: UInt8, first: Bool) -> Bool:
    """Return whether `byte` can appear in an identifier.

    Args:
        byte: One source byte.
        first: True for the first byte.

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


def _skip_ws(raw: Span[UInt8, _], index: Int) -> Int:
    """Skip ASCII whitespace.

    Args:
        raw: The source bytes.
        index: The first byte.

    Returns:
        The first non-whitespace byte.
    """
    var cursor = index
    while cursor < len(raw):
        var byte = raw[cursor]
        if byte != 32 and byte != 9 and byte != 10 and byte != 13:
            break
        cursor += 1
    return cursor


def _word(raw: Span[UInt8, _], index: Int, word: String) -> Int:
    """Return the index after `word`, or -1.

    Args:
        raw: The source bytes.
        index: The first byte.
        word: The identifier.

    Returns:
        The byte after the identifier, or -1 when it is not there.
    """
    var token = word.as_bytes()
    if index > 0 and _name_char(raw[index - 1], False):
        return -1
    if index + len(token) > len(raw):
        return -1
    var offset = 0
    while offset < len(token):
        if raw[index + offset] != token[offset]:
            return -1
        offset += 1
    var end = index + len(token)
    if end < len(raw) and _name_char(raw[end], False):
        return -1
    return end


def _half_rate_end(raw: Span[UInt8, _], index: Int) raises -> Int:
    """Return the end of one half-times-rate product, or -1.

    Args:
        raw: The source bytes.
        index: A candidate start.

    Returns:
        The byte after `rate`, or -1 when the product is not here.

    Raises:
        Error: A number spelling is not a decimal literal.
    """
    var cursor = _word(raw, index, "Expression")
    if cursor < 0:
        return -1
    cursor = _skip_ws(raw, cursor)
    if cursor >= len(raw) or raw[cursor] != 46:
        return -1
    cursor = _word(raw, _skip_ws(raw, cursor + 1), "constant")
    if cursor < 0:
        return -1
    cursor = _skip_ws(raw, cursor)
    if cursor >= len(raw) or raw[cursor] != 40:
        return -1
    cursor = _skip_ws(raw, cursor + 1)
    var start = cursor
    if cursor < len(raw) and (raw[cursor] == 43 or raw[cursor] == 45):
        cursor += 1
    var saw = False
    while cursor < len(raw) and raw[cursor] >= 48 and raw[cursor] <= 57:
        saw = True
        cursor += 1
    if cursor < len(raw) and raw[cursor] == 46:
        cursor += 1
        while cursor < len(raw) and raw[cursor] >= 48 and raw[cursor] <= 57:
            saw = True
            cursor += 1
    if not saw:
        return -1
    var spelling = String()
    var byte = start
    while byte < cursor:
        spelling += chr(Int(raw[byte]))
        byte += 1
    if decimal_word(spelling) != decimal_word("0.5"):
        return -1
    cursor = _skip_ws(raw, cursor)
    if cursor >= len(raw) or raw[cursor] != 41:
        return -1
    cursor = _skip_ws(raw, cursor + 1)
    if cursor >= len(raw) or raw[cursor] != 42:
        return -1
    return _word(raw, _skip_ws(raw, cursor + 1), "rate")


def legacy_rate_half_commutations(text: String) raises -> Int:
    """Return the number of historical half-times-rate products.

    Args:
        text: The legacy ideal spiral source.

    Returns:
        How many `Expression.constant(0.5) * rate` products are present.

    Raises:
        Error: A looked-at number is not a decimal literal.
    """
    var raw = text.as_bytes()
    var count = 0
    var index = 0
    while index < len(raw):
        var end = _half_rate_end(raw, index)
        if end >= 0:
            count += 1
            index = end
        else:
            index += 1
    return count


def require_legacy_rate_halves(text: String) raises:
    """Require exactly two historical half-times-rate products.

    Args:
        text: The legacy ideal spiral source.

    Raises:
        Error: The count is not two.
    """
    if legacy_rate_half_commutations(text) != 2:
        _fail("expected exactly two historical rate-half commutations")
