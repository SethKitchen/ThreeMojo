# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Select one stored spiral operation block.

A block runs from one top-level boundary to the next. Comments and blank
lines stay out of the normalized text. Indentation stays.
"""


def _fail(message: String) raises:
    """Raise an operation-block error.

    Args:
        message: The failure text.

    Raises:
        Error: The block check failed.
    """
    raise Error("spiral moment graph: " + message)


def _is_space(byte: UInt8) -> Bool:
    """Return whether `byte` is ASCII whitespace.

    Args:
        byte: One source byte.

    Returns:
        True for space, tab, newline, carriage return, vertical tab, and
        form feed.
    """
    if byte == 9 or byte == 10 or byte == 11 or byte == 12:
        return True
    if byte == 13 or byte == 32:
        return True
    return False


def _rstrip(text: String) -> String:
    """Drop trailing ASCII whitespace.

    Args:
        text: One line or one block.

    Returns:
        The text without trailing whitespace.
    """
    var raw = text.as_bytes()
    var end = len(raw)
    while end > 0 and _is_space(raw[end - 1]):
        end -= 1
    var body = text[byte=0:end]
    return String(body)


def _lstrip(text: String) -> String:
    """Drop leading ASCII whitespace.

    Args:
        text: One line.

    Returns:
        The text without leading whitespace.
    """
    var raw = text.as_bytes()
    var start = 0
    while start < len(raw) and _is_space(raw[start]):
        start += 1
    var body = text[byte=start:]
    return String(body)


def _split_lines(text: String) -> List[String]:
    """Split `text` on newlines.

    Args:
        text: Source text.

    Returns:
        The lines, without newline characters. A trailing newline does
        not add an empty line.
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


def normalized_block(text: String) -> String:
    """Return the operation text with comments and blank lines removed.

    Args:
        text: One source span.

    Returns:
        The kept lines, with indentation intact, and a final newline.
    """
    var rows = _split_lines(text)
    var kept = List[String]()
    for row in rows:
        var cut = row
        var hash = row.find("#")
        if hash >= 0:
            var head = row[byte=0:hash]
            cut = String(head)
        cut = _rstrip(cut)
        if _lstrip(cut).byte_length() == 0:
            continue
        kept.append(cut)
    var text_out = String()
    var index = 0
    while index < len(kept):
        if index > 0:
            text_out += "\n"
        text_out += kept[index]
        index += 1
    text_out += "\n"
    return text_out


def _count(text: String, needle: String) -> Int:
    """Return the non-overlapping count of `needle`.

    Args:
        text: The source.
        needle: The marker.

    Returns:
        The count.
    """
    var raw = text.as_bytes()
    var token = needle.as_bytes()
    if len(token) == 0:
        return 0
    var count = 0
    var index = 0
    while index + len(token) <= len(raw):
        var same = True
        var offset = 0
        while offset < len(token):
            if raw[index + offset] != token[offset]:
                same = False
                break
            offset += 1
        if same:
            count += 1
            index += len(token)
        else:
            index += 1
    return count


def _find(text: String, needle: String) -> Int:
    """Return the first byte index of `needle`, or -1.

    Args:
        text: The source.
        needle: The marker.

    Returns:
        The byte index, or -1.
    """
    var raw = text.as_bytes()
    var token = needle.as_bytes()
    if len(token) == 0:
        return -1
    var index = 0
    while index + len(token) <= len(raw):
        var same = True
        var offset = 0
        while offset < len(token):
            if raw[index + offset] != token[offset]:
                same = False
                break
            offset += 1
        if same:
            return index
        index += 1
    return -1


def _line_of(text: String, offset: Int) -> Int:
    """Return the 1-based line number of `offset`.

    Args:
        text: The source.
        offset: A byte index.

    Returns:
        The line number.
    """
    var raw = text.as_bytes()
    var line = 1
    var index = 0
    while index < offset and index < len(raw):
        if raw[index] == 10:
            line += 1
        index += 1
    return line


def _name_at(data: Span[UInt8, _], index: Int) -> Int:
    """Return the end of the identifier at `index`, or `index` when absent.

    Args:
        data: The source bytes.
        index: The first byte.

    Returns:
        The byte after the identifier, or `index` when it does not start
        one.
    """
    if index >= len(data):
        return index
    var byte = data[index]
    var start = (
        (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    )
    if not start:
        return index
    var end = index + 1
    while end < len(data):
        var next = data[end]
        var keep = (
            (next >= 65 and next <= 90)
            or (next >= 97 and next <= 122)
            or (next >= 48 and next <= 57)
            or next == 95
        )
        if not keep:
            break
        end += 1
    return end


def _boundary_lines(source: String) raises -> List[Int]:
    """Return the 1-based lines where a top-level boundary starts.

    Args:
        source: Mojo source.

    Returns:
        Each line whose first token is `def`, `from`, or `@` at indent 0.

    Raises:
        Error: The source has a bad indent, an unclosed string, or an
        unclosed bracket.
    """
    var text = source
    if not text.endswith("\n"):
        text += "\n"
    var data = text.as_bytes()
    var levels = List[Int]()
    levels.append(0)
    var starts = List[Int]()
    var index = 0
    var bracket = 0
    var line = 1
    var fresh = True
    while index < len(data):
        var column = 0
        while index < len(data) and (data[index] == 32 or data[index] == 9):
            if data[index] == 9:
                column = column - column % 8 + 8
            else:
                column += 1
            index += 1
        var blank = index >= len(data) or data[index] == 10 or data[index] == 35
        if bracket == 0 and not blank:
            if column > levels[len(levels) - 1]:
                levels.append(column)
            else:
                while column < levels[len(levels) - 1]:
                    _ = levels.pop()
                    if len(levels) == 0:
                        _fail("malformed source-block tokens")
                if column != levels[len(levels) - 1]:
                    _fail("malformed source-block tokens")
        while index < len(data):
            if data[index] == 10 and bracket == 0:
                break
            var byte = data[index]
            if byte == 32 or byte == 9:
                index += 1
                continue
            if byte == 10:
                index += 1
                line += 1
                continue
            if byte == 35:
                while index < len(data) and data[index] != 10:
                    index += 1
                if bracket == 0:
                    break
                continue
            if byte == 34 or byte == 39:
                var quote = byte
                index += 1
                var triple = (
                    index + 1 < len(data)
                    and data[index] == quote
                    and data[index + 1] == quote
                )
                if triple:
                    index += 2
                var closed = False
                while index < len(data):
                    if (
                        triple
                        and index + 2 < len(data)
                        and data[index] == quote
                        and data[index + 1] == quote
                        and data[index + 2] == quote
                    ):
                        index += 3
                        closed = True
                        break
                    if not triple and data[index] == quote:
                        index += 1
                        closed = True
                        break
                    if data[index] == 10:
                        if not triple:
                            _fail("malformed source-block tokens")
                        line += 1
                    index += 1
                if not closed:
                    _fail("malformed source-block tokens")
                fresh = False
                continue
            var name_end = _name_at(data, index)
            if name_end > index:
                var spelling = String(text[byte=index:name_end])
                if (
                    len(levels) == 1
                    and fresh
                    and (spelling == "def" or spelling == "from")
                ):
                    starts.append(line)
                fresh = False
                index = name_end
                continue
            if byte == 64:
                if len(levels) == 1 and fresh:
                    starts.append(line)
                fresh = False
                index += 1
                continue
            if byte == 40 or byte == 91 or byte == 123:
                bracket += 1
            elif byte == 41 or byte == 93 or byte == 125:
                bracket -= 1
                if bracket < 0:
                    _fail("malformed source-block tokens")
            fresh = False
            index += 1
        if index < len(data) and data[index] == 10:
            index += 1
            line += 1
            if bracket == 0 and not blank:
                fresh = True
    if bracket != 0:
        _fail("malformed source-block tokens")
    return starts^


def _has_line(lines: List[Int], line: Int) -> Bool:
    """Return whether `line` is a boundary line.

    Args:
        lines: The boundary lines.
        line: A 1-based line number.

    Returns:
        True when the line is present.
    """
    for item in lines:
        if item == line:
            return True
    return False


def selected_block(text: String, begin: String, end: String) raises -> String:
    """Return the normalized source from `begin` until `end`.

    Args:
        text: The module source.
        begin: The unique top-level start marker.
        end: The unique top-level end marker.

    Returns:
        The normalized operation block, with a final newline.

    Raises:
        Error: A marker is missing, repeated, or not a top-level boundary,
        or a decorator is left outside the block.
    """
    if _count(text, begin) != 1:
        _fail("missing or ambiguous source-block start")
    if _count(text, end) != 1:
        _fail("missing or ambiguous source-block end")
    var start = _find(text, begin)
    var stop = _find(text, end)
    if start >= stop:
        _fail("moved source-block boundary")
    var raw = text.as_bytes()
    if start > 0 and raw[start - 1] != 10:
        _fail("source-block boundary is not top-level")
    if stop > 0 and raw[stop - 1] != 10:
        _fail("source-block boundary is not top-level")
    var lines = _boundary_lines(text)
    if not _has_line(lines, _line_of(text, start)) or not _has_line(
        lines, _line_of(text, stop)
    ):
        _fail("source-block boundary is not an actual top-level token")
    var head = text[byte=0:start]
    var prior = _split_lines(_rstrip(normalized_block(String(head))))
    if len(prior) > 0 and prior[len(prior) - 1].startswith("@"):
        _fail("unbound decorator before source-block start")
    var body = text[byte=start:stop]
    return normalized_block(String(body))
