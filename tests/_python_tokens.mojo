# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Token digests that match CPython 3.12 `tokenize` for these Mojo sources."""

from std.memory import bitcast

from tools._python_float import parse_float
from tools._python_json import PyJson
from tools._sha256 import sha256_hex


comptime _NAME = 1
comptime _NUMBER = 2
comptime _STRING = 3
comptime _NEWLINE = 4
comptime _INDENT = 5
comptime _DEDENT = 6
comptime _OP = 55


def _push(
    mut kinds: List[Int],
    mut texts: List[String],
    mut lines: List[Int],
    mut start_cols: List[Int],
    mut end_lines: List[Int],
    mut end_cols: List[Int],
    kind: Int,
    var text: String,
    line: Int,
    start_col: Int,
    end_line: Int,
    end_col: Int,
):
    """Append one token.

    Args:
        kinds: The token kinds.
        texts: The token texts, in the same order.
        lines: The 1-based line of each token.
        start_cols: The 0-based start column of each token.
        end_lines: The 1-based end line of each token.
        end_cols: The 0-based end column of each token.
        kind: The Python token number.
        text: The token text.
        line: The 1-based line of this token.
        start_col: The 0-based start column.
        end_line: The 1-based end line.
        end_col: The 0-based end column.
    """
    kinds.append(kind)
    texts.append(text^)
    lines.append(line)
    start_cols.append(start_col)
    end_lines.append(end_line)
    end_cols.append(end_col)


def _tokenize(
    source: String, mut kinds: List[Int], mut texts: List[String]
) raises:
    """Tokenize `source` as CPython 3.12 `tokenize.generate_tokens` does.

    The kept tokens are names, numbers, strings, newlines, indents, dedents
    and operators. Comments and blank lines are omitted.

    Args:
        source: Mojo source that uses spaces and ASCII quotes.
        kinds: The token kinds, replaced by this call.
        texts: The token texts, replaced by this call.

    Raises:
        Error: The source has an unclosed string, a bad indent, or an
            unclosed bracket.
    """
    var lines = List[Int]()
    var start_cols = List[Int]()
    var end_lines = List[Int]()
    var end_cols = List[Int]()
    _tokenize_lines(
        source, kinds, texts, lines, start_cols, end_lines, end_cols
    )


def _tokenize_lines(
    source: String,
    mut kinds: List[Int],
    mut texts: List[String],
    mut lines: List[Int],
    mut start_cols: List[Int],
    mut end_lines: List[Int],
    mut end_cols: List[Int],
) raises:
    """Tokenize `source` and record each token's line and column.

    Args:
        source: Mojo source that uses spaces and ASCII quotes.
        kinds: The token kinds, replaced by this call.
        texts: The token texts, replaced by this call.
        lines: The 1-based start line of each token, replaced by this call.
        start_cols: The 0-based start column of each token, replaced by this call.
        end_lines: The 1-based end line of each token, replaced by this call.
        end_cols: The 0-based end column of each token, replaced by this call.

    Raises:
        Error: The source has an unclosed string, a bad indent, or an
            unclosed bracket.
    """
    var text = source
    if not text.endswith("\n"):
        text += "\n"
    var data = text.as_bytes()
    var levels = List[Int]()
    levels.append(0)
    var index = 0
    var depth = 0
    var line_no = 1
    while index < len(data):
        var line_start = index
        var column = 0
        while index < len(data) and (data[index] == 32 or data[index] == 9):
            if data[index] == 9:
                column = column - column % 8 + 8
            else:
                column += 1
            index += 1
        var blank = index >= len(data) or data[index] == 10 or data[index] == 35
        if depth == 0 and not blank:
            if column > levels[len(levels) - 1]:
                var spaces = String(text[byte=line_start:index])
                _push(
                    kinds,
                    texts,
                    lines,
                    start_cols,
                    end_lines,
                    end_cols,
                    _INDENT,
                    spaces^,
                    line_no,
                    0,
                    line_no,
                    index - line_start,
                )
                levels.append(column)
            else:
                while column < levels[len(levels) - 1]:
                    _ = levels.pop()
                    _push(
                        kinds,
                        texts,
                        lines,
                        start_cols,
                        end_lines,
                        end_cols,
                        _DEDENT,
                        String(),
                        line_no,
                        0,
                        line_no,
                        0,
                    )
                if column != levels[len(levels) - 1]:
                    raise Error("invalid source tokens: bad indent")
        while index < len(data):
            if data[index] == 10 and depth == 0:
                break
            var byte = data[index]
            if byte == 32 or byte == 9:
                index += 1
                continue
            if byte == 10:
                index += 1
                line_no += 1
                line_start = index
                continue
            if byte == 35 and depth == 0:
                while index < len(data) and data[index] != 10:
                    index += 1
                break
            if byte == 34 or byte == 39:
                var quote = byte
                var mark = index
                var string_line = line_no
                var string_col = mark - line_start
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
                    if data[index] == 10 and not triple:
                        raise Error("invalid source tokens: unclosed string")
                    if data[index] == 10:
                        line_no += 1
                        line_start = index + 1
                    index += 1
                if not closed:
                    raise Error("invalid source tokens: unclosed string")
                var literal = String(text[byte=mark:index])
                _push(
                    kinds,
                    texts,
                    lines,
                    start_cols,
                    end_lines,
                    end_cols,
                    _STRING,
                    literal^,
                    string_line,
                    string_col,
                    line_no,
                    index - line_start,
                )
                continue
            var name_start = (
                (byte >= 65 and byte <= 90)
                or (byte >= 97 and byte <= 122)
                or byte == 95
            )
            if name_start:
                var mark = index
                index += 1
                while index < len(data):
                    var next = data[index]
                    var keep = (
                        (next >= 65 and next <= 90)
                        or (next >= 97 and next <= 122)
                        or (next >= 48 and next <= 57)
                        or next == 95
                    )
                    if not keep:
                        break
                    index += 1
                var name = String(text[byte=mark:index])
                _push(
                    kinds,
                    texts,
                    lines,
                    start_cols,
                    end_lines,
                    end_cols,
                    _NAME,
                    name^,
                    line_no,
                    mark - line_start,
                    line_no,
                    index - line_start,
                )
                continue
            var number_start = (byte >= 48 and byte <= 57) or (
                byte == 46
                and index + 1 < len(data)
                and data[index + 1] >= 48
                and data[index + 1] <= 57
            )
            if number_start:
                var mark = index
                if byte != 46:
                    while (
                        index < len(data)
                        and data[index] >= 48
                        and data[index] <= 57
                    ):
                        index += 1
                    if (
                        index == mark + 1
                        and data[mark] == 48
                        and index < len(data)
                    ):
                        var base = data[index]
                        var based = (
                            base == 120
                            or base == 88
                            or base == 98
                            or base == 66
                            or base == 111
                            or base == 79
                        )
                        if based:
                            var end = index + 1
                            while end < len(data):
                                var digit = data[end]
                                var hex_digit = (
                                    (digit >= 48 and digit <= 57)
                                    or (digit >= 65 and digit <= 70)
                                    or (digit >= 97 and digit <= 102)
                                )
                                var ok = digit == 48 or digit == 49
                                if base == 111 or base == 79:
                                    ok = digit >= 48 and digit <= 55
                                elif base == 120 or base == 88:
                                    ok = hex_digit
                                if not ok:
                                    break
                                end += 1
                            if end > index + 1:
                                index = end
                                var prefixed = String(text[byte=mark:index])
                                _push(
                                    kinds,
                                    texts,
                                    lines,
                                    start_cols,
                                    end_lines,
                                    end_cols,
                                    _NUMBER,
                                    prefixed^,
                                    line_no,
                                    mark - line_start,
                                    line_no,
                                    index - line_start,
                                )
                                continue
                if (
                    index < len(data)
                    and data[index] == 46
                    and index + 1 < len(data)
                    and data[index + 1] >= 48
                    and data[index + 1] <= 57
                ):
                    index += 1
                    while (
                        index < len(data)
                        and data[index] >= 48
                        and data[index] <= 57
                    ):
                        index += 1
                if index < len(data) and (
                    data[index] == 101 or data[index] == 69
                ):
                    var exponent = index + 1
                    if exponent < len(data) and (
                        data[exponent] == 43 or data[exponent] == 45
                    ):
                        exponent += 1
                    if (
                        exponent < len(data)
                        and data[exponent] >= 48
                        and data[exponent] <= 57
                    ):
                        index = exponent + 1
                        while (
                            index < len(data)
                            and data[index] >= 48
                            and data[index] <= 57
                        ):
                            index += 1
                var number = String(text[byte=mark:index])
                _push(
                    kinds,
                    texts,
                    lines,
                    start_cols,
                    end_lines,
                    end_cols,
                    _NUMBER,
                    number^,
                    line_no,
                    mark - line_start,
                    line_no,
                    index - line_start,
                )
                continue
            var three = String()
            if index + 2 < len(data):
                three = String(text[byte = index : index + 3])
            if (
                three == "**="
                or three == "//="
                or three == "<<="
                or three == ">>="
                or three == "..."
            ):
                var op_col = index - line_start
                _push(
                    kinds,
                    texts,
                    lines,
                    start_cols,
                    end_lines,
                    end_cols,
                    _OP,
                    three^,
                    line_no,
                    op_col,
                    line_no,
                    op_col + 3,
                )
                index += 3
                continue
            var two = String()
            if index + 1 < len(data):
                two = String(text[byte = index : index + 2])
            if (
                two == "!="
                or two == "+="
                or two == "-="
                or two == "*="
                or two == "/="
                or two == "%="
                or two == "&="
                or two == "|="
                or two == "^="
                or two == "<<"
                or two == ">>"
                or two == "->"
                or two == "<="
                or two == ">="
                or two == "=="
                or two == "//"
                or two == "**"
            ):
                var op_col = index - line_start
                _push(
                    kinds,
                    texts,
                    lines,
                    start_cols,
                    end_lines,
                    end_cols,
                    _OP,
                    two^,
                    line_no,
                    op_col,
                    line_no,
                    op_col + 2,
                )
                index += 2
                continue
            if byte == 40 or byte == 91 or byte == 123:
                depth += 1
            elif byte == 41 or byte == 93 or byte == 125:
                depth -= 1
                if depth < 0:
                    raise Error("invalid source tokens: extra closer")
            var operator = String(chr(Int(byte)))
            var op_col = index - line_start
            _push(
                kinds,
                texts,
                lines,
                start_cols,
                end_lines,
                end_cols,
                _OP,
                operator^,
                line_no,
                op_col,
                line_no,
                op_col + 1,
            )
            index += 1
        if index < len(data) and data[index] == 10:
            if depth == 0 and not blank:
                var newline_col = index - line_start
                _push(
                    kinds,
                    texts,
                    lines,
                    start_cols,
                    end_lines,
                    end_cols,
                    _NEWLINE,
                    String("\n"),
                    line_no,
                    newline_col,
                    line_no,
                    newline_col + 1,
                )
            index += 1
            line_no += 1
    if depth != 0:
        raise Error("invalid source tokens: unclosed bracket")
    while len(levels) > 1:
        _ = levels.pop()
        _push(
            kinds,
            texts,
            lines,
            start_cols,
            end_lines,
            end_cols,
            _DEDENT,
            String(),
            line_no,
            0,
            line_no,
            0,
        )


def _keep_executable(
    mut kinds: List[Int],
    mut texts: List[String],
    mut start_lines: List[Int],
    mut start_cols: List[Int],
    mut end_lines: List[Int],
    mut end_cols: List[Int],
    read_kinds: List[Int],
    read_texts: List[String],
    read_lines: List[Int],
    read_start_cols: List[Int],
    read_end_lines: List[Int],
    read_end_cols: List[Int],
):
    """Keep executable tokens and drop a comma before a closer.

    Args:
        kinds: The kept kinds.
        texts: The kept texts.
        start_lines: The kept start lines.
        start_cols: The kept start columns.
        end_lines: The kept end lines.
        end_cols: The kept end columns.
        read_kinds: The tokenizer kinds.
        read_texts: The tokenizer texts.
        read_lines: The tokenizer start lines.
        read_start_cols: The tokenizer start columns.
        read_end_lines: The tokenizer end lines.
        read_end_cols: The tokenizer end columns.
    """
    var kept_kinds = List[Int]()
    var kept_texts = List[String]()
    var kept_lines = List[Int]()
    var kept_start_cols = List[Int]()
    var kept_end_lines = List[Int]()
    var kept_end_cols = List[Int]()
    var index = 0
    while index < len(read_kinds):
        var kind = read_kinds[index]
        if kind != _NEWLINE and kind != _INDENT and kind != _DEDENT:
            kept_kinds.append(kind)
            kept_texts.append(read_texts[index])
            kept_lines.append(read_lines[index])
            kept_start_cols.append(read_start_cols[index])
            kept_end_lines.append(read_end_lines[index])
            kept_end_cols.append(read_end_cols[index])
        index += 1
    index = 0
    while index < len(kept_kinds):
        var comma = (
            kept_texts[index] == ","
            and index + 1 < len(kept_kinds)
            and (kept_texts[index + 1] == ")" or kept_texts[index + 1] == "]")
        )
        if not comma:
            kinds.append(kept_kinds[index])
            texts.append(kept_texts[index])
            start_lines.append(kept_lines[index])
            start_cols.append(kept_start_cols[index])
            end_lines.append(kept_end_lines[index])
            end_cols.append(kept_end_cols[index])
        index += 1


def _leading_space_count(text: String) -> Int:
    """Return the number of leading spaces and tabs.

    Args:
        text: The replacement text.

    Returns:
        The byte count of the leading space and tab prefix.
    """
    var data = text.as_bytes()
    var index = 0
    while index < len(data) and (data[index] == 32 or data[index] == 9):
        index += 1
    return index


def replace_token_fragment(
    source: String, before: String, after: String
) raises -> String:
    """Replace one executable token fragment.

    Comments and a formatter's trailing comma cannot move the match.

    Args:
        source: The original source.
        before: The fragment to find.
        after: The replacement. Leading spaces and tabs are removed.

    Returns:
        The source with that one fragment replaced.

    Raises:
        Error: The fragment is missing or occurs more than once.
    """
    var source_kinds = List[Int]()
    var source_texts = List[String]()
    var source_lines = List[Int]()
    var source_start_cols = List[Int]()
    var source_end_lines = List[Int]()
    var source_end_cols = List[Int]()
    _tokenize_lines(
        source,
        source_kinds,
        source_texts,
        source_lines,
        source_start_cols,
        source_end_lines,
        source_end_cols,
    )
    var before_kinds = List[Int]()
    var before_texts = List[String]()
    var before_lines = List[Int]()
    var before_start_cols = List[Int]()
    var before_end_lines = List[Int]()
    var before_end_cols = List[Int]()
    _tokenize_lines(
        before,
        before_kinds,
        before_texts,
        before_lines,
        before_start_cols,
        before_end_lines,
        before_end_cols,
    )
    var kinds = List[Int]()
    var texts = List[String]()
    var start_lines = List[Int]()
    var start_cols = List[Int]()
    var end_lines = List[Int]()
    var end_cols = List[Int]()
    _keep_executable(
        kinds,
        texts,
        start_lines,
        start_cols,
        end_lines,
        end_cols,
        source_kinds,
        source_texts,
        source_lines,
        source_start_cols,
        source_end_lines,
        source_end_cols,
    )
    var wanted_kinds = List[Int]()
    var wanted_texts = List[String]()
    var ignored_lines = List[Int]()
    var ignored_start_cols = List[Int]()
    var ignored_end_lines = List[Int]()
    var ignored_end_cols = List[Int]()
    _keep_executable(
        wanted_kinds,
        wanted_texts,
        ignored_lines,
        ignored_start_cols,
        ignored_end_lines,
        ignored_end_cols,
        before_kinds,
        before_texts,
        before_lines,
        before_start_cols,
        before_end_lines,
        before_end_cols,
    )
    var matches = List[Int]()
    var start = 0
    while start + len(wanted_kinds) <= len(kinds) and len(wanted_kinds) > 0:
        var same = True
        var cursor = 0
        while same and cursor < len(wanted_kinds):
            if (
                kinds[start + cursor] != wanted_kinds[cursor]
                or texts[start + cursor] != wanted_texts[cursor]
            ):
                same = False
            cursor += 1
        if same:
            matches.append(start)
        start += 1
    if len(matches) != 1:
        raise Error(
            "missing or ambiguous executable mutation fragment: " + before
        )
    var first = matches[0]
    var last = first + len(wanted_kinds) - 1
    var offsets = List[Int]()
    offsets.append(0)
    var data = source.as_bytes()
    var index = 0
    while index < len(data):
        if data[index] == 10:
            offsets.append(index + 1)
        index += 1
    var start_at = offsets[start_lines[first] - 1] + start_cols[first]
    var end_at = offsets[end_lines[last] - 1] + end_cols[last]
    var skip = _leading_space_count(after)
    return (
        String(source[byte=:start_at])
        + String(after[byte=skip:])
        + String(source[byte=end_at:])
    )


def significant_json(source: String) raises -> String:
    """Return the canonical significant-token JSON.

    Args:
        source: Mojo source.

    Returns:
        The JSON list of `[kind, text]` pairs, without comments or blank lines.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var doc = PyJson()
    var rows = doc.new_list()
    var index = 0
    while index < len(kinds):
        _append_token(doc, rows, kinds[index], texts[index])
        index += 1
    doc.root = rows
    return doc.dumps()


def token_sha256(source: String) raises -> String:
    """Return the SHA-256 of the kept tokens, as CPython 3.12 does.

    Args:
        source: Mojo source.

    Returns:
        The hex digest of the canonical JSON token list.

    Raises:
        Error: The source cannot be tokenized.
    """
    return sha256_hex(significant_json(source).as_bytes())


def _kept_lines(source: String) -> List[String]:
    """Split `source` into lines that keep their newlines.

    Args:
        source: The original module text.

    Returns:
        Each physical line, including a trailing newline when present.
    """
    var lines = List[String]()
    var data = source.as_bytes()
    var start = 0
    var index = 0
    while index < len(data):
        if data[index] == 10:
            lines.append(String(source[byte = start : index + 1]))
            start = index + 1
        index += 1
    if start < len(data):
        lines.append(String(source[byte=start:]))
    return lines^


def _leading_indent(line: String) -> String:
    """Return the leading spaces and tabs of a content line.

    Args:
        line: One line without its newline.

    Returns:
        The leading whitespace, or empty when the line is blank.
    """
    var data = line.as_bytes()
    var index = 0
    while index < len(data) and (data[index] == 32 or data[index] == 9):
        index += 1
    if index == len(data):
        return String("")
    return String(line[byte=:index])


def _only_whitespace(line: String) -> Bool:
    """Return whether `line` is empty or holds only spaces and tabs.

    Args:
        line: One line without its newline.

    Returns:
        True when the line has no other characters.
    """
    var data = line.as_bytes()
    var index = 0
    while index < len(data):
        if data[index] != 32 and data[index] != 9:
            return False
        index += 1
    return True


def _dedent(text: String) -> String:
    """Remove the common leading whitespace, as Python `textwrap.dedent` does.

    Args:
        text: The declaration slice.

    Returns:
        The same text with the shared indent removed.
    """
    var parts = List[String]()
    var data = text.as_bytes()
    var start = 0
    var index = 0
    while index < len(data):
        if data[index] == 10:
            parts.append(String(text[byte=start:index]))
            start = index + 1
        index += 1
    parts.append(String(text[byte=start:]))
    var margin = String("")
    var have_margin = False
    var row = 0
    while row < len(parts):
        var part = parts[row]
        if not _only_whitespace(part):
            var indent = _leading_indent(part)
            if not have_margin:
                margin = indent
                have_margin = True
            elif indent.startswith(margin):
                pass
            elif margin.startswith(indent):
                margin = indent
            else:
                var margin_bytes = margin.as_bytes()
                var indent_bytes = indent.as_bytes()
                var count = 0
                var limit = len(margin_bytes)
                if len(indent_bytes) < limit:
                    limit = len(indent_bytes)
                while (
                    count < limit and margin_bytes[count] == indent_bytes[count]
                ):
                    count += 1
                var next_margin = String("")
                var margin_data = margin.as_bytes()
                var copy_at = 0
                while copy_at < count:
                    next_margin += chr(Int(margin_data[copy_at]))
                    copy_at += 1
                margin = next_margin^
        row += 1
    var out = String("")
    row = 0
    while row < len(parts):
        if row > 0:
            out += "\n"
        var line = parts[row]
        if _only_whitespace(line):
            line = String("")
        elif margin.byte_length() > 0 and line.startswith(margin):
            var next_line = String("")
            var line_data = line.as_bytes()
            var copy_at = margin.byte_length()
            while copy_at < len(line_data):
                next_line += chr(Int(line_data[copy_at]))
                copy_at += 1
            line = next_line^
        out += line
        row += 1
    return out


def _clear_decorator(mut decorators: List[Int], depth: Int):
    """Forget a decorator recorded at `depth`.

    Args:
        decorators: The first decorator token at each depth, or -1.
        depth: The scope depth being left or entered.
    """
    while len(decorators) <= depth:
        decorators.append(-1)
    decorators[depth] = -1


def _note_decorator(mut decorators: List[Int], depth: Int, token: Int):
    """Record the first decorator at `depth`.

    Args:
        decorators: The first decorator token at each depth, or -1.
        depth: The scope depth of the decorator.
        token: The `@` token index.
    """
    while len(decorators) <= depth:
        decorators.append(-1)
    if decorators[depth] < 0:
        decorators[depth] = token


def _take_decorator(mut decorators: List[Int], depth: Int) -> Int:
    """Return and clear the decorator at `depth`.

    Args:
        decorators: The first decorator token at each depth, or -1.
        depth: The scope depth of the following declaration.

    Returns:
        The `@` token index, or -1 when there is no decorator.
    """
    while len(decorators) <= depth:
        decorators.append(-1)
    var value = decorators[depth]
    decorators[depth] = -1
    return value


struct DeclarationPlace:
    """One dedented declaration and its half-open source line span."""

    var text: String
    """The declaration text, with the shared indent removed."""
    var first: Int
    """The first source line, starting at 0."""
    var last: Int
    """The line after the declaration, starting at 0."""

    def __init__(out self, text: String, first: Int, last: Int):
        """Store one declaration span.

        Args:
            text: The dedented declaration.
            first: The first source line, starting at 0.
            last: The line after the declaration, starting at 0.
        """
        self.text = text
        self.first = first
        self.last = last


def declaration_text(
    source: String, name: String, owners: List[String]
) raises -> String:
    """Return one dedented declaration, including its first decorator.

    Args:
        source: Mojo source.
        name: The function name.
        owners: The enclosing struct names, from the outside inward.

    Returns:
        The declaration text, with the shared indent removed.

    Raises:
        Error: The function is missing, repeated, owned by another scope,
            or has no indented body.
    """
    var place = declaration_place(source, name, owners)
    return place.text


def declaration_place(
    source: String, name: String, owners: List[String]
) raises -> DeclarationPlace:
    """Return one declaration and the source lines it occupies.

    Args:
        source: Mojo source.
        name: The function name.
        owners: The enclosing struct names, from the outside inward.

    Returns:
        The dedented text and the half-open line span.

    Raises:
        Error: The function is missing, repeated, owned by another scope,
            or has no indented body.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    var lines = List[Int]()
    var start_cols = List[Int]()
    var token_end_lines = List[Int]()
    var end_cols = List[Int]()
    _tokenize_lines(
        source,
        kinds,
        texts,
        lines,
        start_cols,
        token_end_lines,
        end_cols,
    )
    var scope_kinds = List[String]()
    var scope_names = List[String]()
    var pending_kind = String("")
    var pending_name = String("")
    var has_pending = False
    var decorators = List[Int]()
    var statement = List[Int]()
    var hits = 0
    var begin = 0
    var signature = 0
    var saved_kinds = List[String]()
    var saved_names = List[String]()
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            if has_pending:
                scope_kinds.append(pending_kind)
                scope_names.append(pending_name)
            else:
                scope_kinds.append("block")
                scope_names.append("")
            has_pending = False
            _clear_decorator(decorators, len(scope_kinds))
        elif kind == _DEDENT:
            if len(scope_kinds) == 0:
                raise Error("unmatched source scope")
            _clear_decorator(decorators, len(scope_kinds))
            _ = scope_kinds.pop()
            _ = scope_names.pop()
            has_pending = False
        elif kind == _NEWLINE:
            if len(statement) > 0:
                var first = statement[0]
                var words0 = texts[first]
                var last = texts[statement[len(statement) - 1]]
                var depth = len(scope_kinds)
                if words0 == "@":
                    _note_decorator(decorators, depth, first)
                else:
                    var preceding = _take_decorator(decorators, depth)
                    if (
                        len(statement) >= 2
                        and words0 == "def"
                        and texts[statement[1]] == name
                    ):
                        hits += 1
                        if hits == 1:
                            if preceding >= 0:
                                begin = preceding
                            else:
                                begin = first
                            signature = index
                            saved_kinds.clear()
                            saved_names.clear()
                            var slot = 0
                            while slot < len(scope_kinds):
                                saved_kinds.append(scope_kinds[slot])
                                saved_names.append(scope_names[slot])
                                slot += 1
                if last == ":":
                    if len(statement) >= 2 and (
                        words0 == "def"
                        or words0 == "struct"
                        or words0 == "trait"
                        or words0 == "class"
                    ):
                        pending_kind = words0
                        pending_name = texts[statement[1]]
                        has_pending = True
                    else:
                        pending_kind = "block"
                        pending_name = ""
                        has_pending = True
                else:
                    has_pending = False
            statement.clear()
        else:
            statement.append(index)
        index += 1
    if hits != 1:
        raise Error("missing or ambiguous actual guard declaration: " + name)
    if len(saved_kinds) != len(owners):
        raise Error("guard caller owner/scope changed: " + name)
    var slot = 0
    while slot < len(owners):
        if saved_kinds[slot] != "struct" or saved_names[slot] != owners[slot]:
            raise Error("guard caller owner/scope changed: " + name)
        slot += 1
    var body = signature + 1
    if body >= len(kinds) or kinds[body] != _INDENT:
        raise Error("unsupported guard function body: " + name)
    var end = body + 1
    var nest = 1
    while end < len(kinds) and nest > 0:
        if kinds[end] == _INDENT:
            nest += 1
        elif kinds[end] == _DEDENT:
            nest -= 1
        end += 1
    if nest != 0:
        raise Error("unclosed guard function body: " + name)
    var kept = _kept_lines(source)
    var first_line = lines[begin] - 1
    var last_line = lines[end - 1] - 1
    if last_line > len(kept):
        last_line = len(kept)
    if first_line < 0 or last_line < first_line:
        raise Error("empty actual guard function: " + name)
    var piece = String("")
    var line = first_line
    while line < last_line:
        piece += kept[line]
        line += 1
    var result = _dedent(piece)
    var content = result.as_bytes()
    var cursor = 0
    var blank = True
    while cursor < len(content):
        var byte = content[cursor]
        if byte != 32 and byte != 9 and byte != 10 and byte != 13:
            blank = False
            break
        cursor += 1
    if blank:
        raise Error("empty actual guard function: " + name)
    return DeclarationPlace(result, first_line, last_line)


def declaration_routing(source: String) raises -> String:
    """Return the declaration routing JSON, without function suites.

    Args:
        source: Mojo source.

    Returns:
        The canonical routing document.

    Raises:
        Error: A scope is unmatched or the routing does not finish.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var doc = PyJson()
    var rows = doc.new_list()
    var scope_kinds = List[String]()
    var scope_names = List[String]()
    var scope_starts = List[Int]()
    var scope_counts = List[Int]()
    var block_words = List[String]()
    var pending_kind = String("")
    var pending_name = String("")
    var pending_words = List[String]()
    var has_pending = False
    var pending_block = False
    var statement_kinds = List[Int]()
    var statement_texts = List[String]()
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            if not has_pending:
                scope_kinds.append("block")
                scope_names.append("")
                scope_starts.append(len(block_words))
                scope_counts.append(0)
            elif pending_block:
                scope_kinds.append("block")
                scope_names.append("")
                scope_starts.append(len(block_words))
                scope_counts.append(len(pending_words))
                var word = 0
                while word < len(pending_words):
                    block_words.append(pending_words[word])
                    word += 1
            else:
                scope_kinds.append(pending_kind)
                scope_names.append(pending_name)
                scope_starts.append(0)
                scope_counts.append(0)
            has_pending = False
            pending_block = False
            pending_words.clear()
        elif kind == _DEDENT:
            if len(scope_kinds) == 0:
                raise Error("unmatched routing scope")
            var count = scope_counts.pop()
            _ = scope_starts.pop()
            _ = scope_kinds.pop()
            _ = scope_names.pop()
            var left = len(block_words) - count
            while len(block_words) > left:
                _ = block_words.pop()
            has_pending = False
            pending_block = False
            pending_words.clear()
        elif kind == _NEWLINE:
            if len(statement_kinds) > 0:
                var inside_def = False
                var scope_index = 0
                while scope_index < len(scope_kinds):
                    if scope_kinds[scope_index] == "def":
                        inside_def = True
                    scope_index += 1
                if not inside_def:
                    var scopes = doc.new_list()
                    var scope = 0
                    while scope < len(scope_kinds):
                        var pair = doc.new_list()
                        doc.append(pair, doc.new_str(scope_kinds[scope]))
                        if scope_kinds[scope] == "block":
                            var payload = doc.new_list()
                            var word = 0
                            while word < scope_counts[scope]:
                                doc.append(
                                    payload,
                                    doc.new_str(
                                        block_words[scope_starts[scope] + word]
                                    ),
                                )
                                word += 1
                            doc.append(pair, payload)
                        else:
                            doc.append(pair, doc.new_str(scope_names[scope]))
                        doc.append(scopes, pair)
                        scope += 1
                    var statement = doc.new_list()
                    var token = 0
                    while token < len(statement_kinds):
                        var pair = doc.new_list()
                        doc.append(pair, doc.new_int(statement_kinds[token]))
                        doc.append(pair, doc.new_str(statement_texts[token]))
                        doc.append(statement, pair)
                        token += 1
                    var row = doc.new_list()
                    doc.append(row, scopes)
                    doc.append(row, statement)
                    doc.append(rows, row)
                var last = statement_texts[len(statement_texts) - 1]
                if last == ":":
                    var first = statement_texts[0]
                    if len(statement_texts) >= 2 and (
                        first == "def"
                        or first == "struct"
                        or first == "trait"
                        or first == "class"
                    ):
                        pending_kind = first
                        pending_name = statement_texts[1]
                        pending_block = False
                        has_pending = True
                        pending_words.clear()
                    else:
                        pending_block = True
                        has_pending = True
                        pending_words.clear()
                        var word = 0
                        while word < len(statement_texts):
                            pending_words.append(statement_texts[word])
                            word += 1
                else:
                    has_pending = False
                    pending_block = False
                    pending_words.clear()
            statement_kinds.clear()
            statement_texts.clear()
        else:
            statement_kinds.append(kind)
            statement_texts.append(texts[index])
        index += 1
    if len(statement_kinds) > 0 or len(scope_kinds) > 0:
        raise Error("incomplete declaration routing")
    doc.root = rows
    return doc.dumps()


def _token_name(kind: Int) -> String:
    """Return the Python token name for one kept kind.

    Args:
        kind: The Python token number.

    Returns:
        `NAME`, `NUMBER`, `STRING`, or `OP`.
    """
    if kind == _NAME:
        return "NAME"
    if kind == _NUMBER:
        return "NUMBER"
    if kind == _STRING:
        return "STRING"
    return "OP"


def ideal_function_source(source: String, name: String) raises -> String:
    """Return one generic function with `var`, `comptime`, and its parameter list removed.

    Args:
        source: Mojo source that starts at `def NAME[`.
        name: The function name.

    Returns:
        Source Python's parser accepts as that function.

    Raises:
        Error: The declaration is not `def NAME[derivatives: Bool]`, or the
            source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    try:
        _tokenize(source, kinds, texts)
    except error:
        _ = String(error)
        raise Error("unsupported ideal source syntax")
    var kept_kinds = List[Int]()
    var kept_texts = List[String]()
    var index = 0
    while index < len(kinds):
        if not (
            kinds[index] == _NAME
            and (texts[index] == "var" or texts[index] == "comptime")
        ):
            kept_kinds.append(kinds[index])
            kept_texts.append(texts[index])
        index += 1
    if (
        len(kept_kinds) < 3
        or kept_kinds[0] != _NAME
        or kept_texts[0] != "def"
        or kept_kinds[1] != _NAME
        or kept_texts[1] != name
        or kept_kinds[2] != _OP
        or kept_texts[2] != "["
    ):
        raise Error("unsupported ideal function declaration")
    var begin = 2
    var end = begin + 1
    var depth = 1
    while end < len(kept_kinds) and depth > 0:
        if kept_texts[end] == "[":
            depth += 1
        elif kept_texts[end] == "]":
            depth -= 1
        end += 1
    if depth != 0:
        raise Error("unclosed ideal generic declaration")
    var parameters = List[String]()
    var parameter_kinds = List[String]()
    var token = begin + 1
    while token < end - 1:
        if (
            kept_kinds[token] != _NEWLINE
            and kept_kinds[token] != _INDENT
            and kept_kinds[token] != _DEDENT
        ):
            parameter_kinds.append(_token_name(kept_kinds[token]))
            parameters.append(kept_texts[token])
        token += 1
    if len(parameters) > 0 and parameters[len(parameters) - 1] == ",":
        _ = parameters.pop()
        _ = parameter_kinds.pop()
    var expected_kinds = List[String]()
    expected_kinds.append("NAME")
    expected_kinds.append("OP")
    expected_kinds.append("NAME")
    var expected_texts = List[String]()
    expected_texts.append("derivatives")
    expected_texts.append(":")
    expected_texts.append("Bool")
    var same = len(parameters) == len(expected_texts)
    var check = 0
    while same and check < len(parameters):
        if (
            parameter_kinds[check] != expected_kinds[check]
            or parameters[check] != expected_texts[check]
        ):
            same = False
        check += 1
    if not same:
        raise Error("changed ideal generic declaration")
    var out_kinds = List[Int]()
    var out_texts = List[String]()
    token = 0
    while token < begin:
        out_kinds.append(kept_kinds[token])
        out_texts.append(kept_texts[token])
        token += 1
    token = end
    while token < len(kept_kinds):
        out_kinds.append(kept_kinds[token])
        out_texts.append(kept_texts[token])
        token += 1
    var out = String("")
    var indents = List[String]()
    indents.append("")
    var need_indent = False
    token = 0
    while token < len(out_kinds):
        var kind = out_kinds[token]
        if kind == _NEWLINE:
            out += "\n"
            need_indent = True
        elif kind == _DEDENT:
            if len(indents) > 1:
                _ = indents.pop()
        elif kind == _INDENT:
            indents.append(out_texts[token])
        else:
            if need_indent:
                out += indents[len(indents) - 1]
                need_indent = False
            elif out.byte_length() > 0:
                var data = out.as_bytes()
                if data[len(data) - 1] != 10:
                    out += " "
            out += out_texts[token]
        token += 1
    return out


def _name_byte(byte: UInt8) -> Bool:
    """Return whether `byte` can appear inside an identifier.

    Args:
        byte: One source byte.

    Returns:
        True for ASCII letters, digits, and underscore.
    """
    if byte >= 48 and byte <= 57:
        return True
    if byte >= 65 and byte <= 90:
        return True
    if byte >= 97 and byte <= 122:
        return True
    return byte == 95


def _is_space_byte(byte: UInt8) -> Bool:
    """Return whether `byte` is ASCII whitespace.

    Args:
        byte: One source byte.

    Returns:
        True for space, tab, and newlines.
    """
    return byte == 9 or byte == 10 or byte == 13 or byte == 32


def _ends_with_word(data: Span[UInt8, _], end: Int, word: String) -> Bool:
    """Return whether `word` ends the text before `end`, ignoring trailing space.

    Args:
        data: The source bytes.
        end: The index after the examined prefix.
        word: The identifier to match.

    Returns:
        True when that identifier is the last word and is not part of a longer
        name.
    """
    var cursor = end
    while cursor > 0 and _is_space_byte(data[cursor - 1]):
        cursor -= 1
    var needle = word.as_bytes()
    if cursor < len(needle):
        return False
    var start = cursor - len(needle)
    var index = 0
    while index < len(needle):
        if data[start + index] != needle[index]:
            return False
        index += 1
    if start > 0 and _name_byte(data[start - 1]):
        return False
    return True


def _skip_gap(data: Span[UInt8, _], index: Int) -> Int:
    """Return the next index that is not a space or a tab.

    Args:
        data: The source bytes.
        index: The start index.

    Returns:
        The index of the next byte that is not a space or tab, or the end.
    """
    var cursor = index
    while cursor < len(data) and (data[cursor] == 9 or data[cursor] == 32):
        cursor += 1
    return cursor


def _skip_space(data: Span[UInt8, _], index: Int) -> Int:
    """Return the next non-space index.

    Args:
        data: The source bytes.
        index: The start index.

    Returns:
        The index of the next non-space byte, or the end.
    """
    var cursor = index
    while cursor < len(data) and _is_space_byte(data[cursor]):
        cursor += 1
    return cursor


def _read_name(data: Span[UInt8, _], index: Int) -> String:
    """Return the identifier at `index`.

    Args:
        data: The source bytes.
        index: The first byte of the identifier.

    Returns:
        The identifier, or empty when `index` does not start one.
    """
    var cursor = index
    var out = String("")
    while cursor < len(data) and _name_byte(data[cursor]):
        out += chr(Int(data[cursor]))
        cursor += 1
    return out


def _assignment_after(data: Span[UInt8, _], index: Int) -> Bool:
    """Return whether `=` that is not `==` follows `index`.

    Args:
        data: The source bytes.
        index: The first byte to inspect.

    Returns:
        True when the next non-space character is a single equals sign.
    """
    var cursor = _skip_space(data, index)
    if cursor >= len(data) or data[cursor] != 61:
        return False
    return cursor + 1 >= len(data) or data[cursor + 1] != 61


def check_stored_half(source: String) raises:
    """Require the stored-half helper to keep its reviewed result uses.

    Args:
        source: Mojo source beginning at `def _stored_half[`.

    Raises:
        Error: The declaration, the initial half product, a return, or a use
            of `result` changed.
    """
    var normalized = ideal_function_source(source, "_stored_half")
    var lines = List[String]()
    var current = String("")
    var data = normalized.as_bytes()
    var index = 0
    while index < len(data):
        if data[index] == 10:
            lines.append(current)
            current = String("")
        else:
            current += chr(Int(data[index]))
        index += 1
    if current.byte_length() > 0:
        lines.append(current)
    var header = String(
        "def _stored_half ( value : _JetExpression [ derivatives ] , ) -> "
        + "_JetExpression [ derivatives ] :"
    )
    var first = String(
        "    result = value * _JetExpression [ derivatives ] . constant ( 0.5 )"
    )
    if len(lines) == 0 or lines[0] != header:
        raise Error("ideal helper declaration or decorator changed")
    if len(lines) < 2 or lines[1] != first:
        raise Error("ideal helper initial expression changed")
    var line = 2
    while line < len(lines):
        if lines[line].startswith("def "):
            raise Error("ambiguous ideal function declaration")
        line += 1
    var body = String("")
    line = 2
    while line < len(lines):
        if body.byte_length() > 0:
            body += "\n"
        body += lines[line]
        line += 1
    var bytes = body.as_bytes()
    var needle = "result".as_bytes()
    index = 0
    while index + len(needle) <= len(bytes):
        var fits = True
        var cursor = 0
        while fits and cursor < len(needle):
            if bytes[index + cursor] != needle[cursor]:
                fits = False
            cursor += 1
        var left = index == 0 or not _name_byte(bytes[index - 1])
        var right = index + len(needle) == len(bytes) or not _name_byte(
            bytes[index + len(needle)]
        )
        if fits and left and right:
            var after = index + len(needle)
            if _ends_with_word(bytes, index, "return"):
                var stop = _skip_gap(bytes, after)
                if stop < len(bytes) and bytes[stop] != 10:
                    raise Error("ideal helper return changed")
            elif _assignment_after(bytes, after) and _statement_start(
                bytes, index
            ):
                raise Error("ideal helper result rebound")
            else:
                var attribute = _skip_space(bytes, after)
                if attribute < len(bytes) and bytes[attribute] == 46:
                    var name = _read_name(
                        bytes, _skip_space(bytes, attribute + 1)
                    )
                    var name_at = _skip_space(bytes, attribute + 1)
                    if name.byte_length() > 0 and _assignment_after(
                        bytes, name_at + name.byte_length()
                    ):
                        if name != "error":
                            raise Error("non-error result field changed")
                    elif _call_argument(bytes, index):
                        raise Error("ideal helper result escapes")
                    else:
                        raise Error("unapproved ideal helper result use")
                elif _call_argument(bytes, index):
                    raise Error("ideal helper result escapes")
                else:
                    raise Error("unapproved ideal helper result use")
            index = after
            continue
        index += 1
    index = 0
    var ret = "return".as_bytes()
    while index + len(ret) <= len(bytes):
        var found = True
        var at = 0
        while found and at < len(ret):
            if bytes[index + at] != ret[at]:
                found = False
            at += 1
        var edge = index == 0 or not _name_byte(bytes[index - 1])
        var tail = index + len(ret)
        var word_edge = tail == len(bytes) or not _name_byte(bytes[tail])
        if found and edge and word_edge:
            var name_at = _skip_gap(bytes, tail)
            var value = _read_name(bytes, name_at)
            var stop = _skip_gap(bytes, name_at + value.byte_length())
            var more = stop < len(bytes) and bytes[stop] != 10
            if value != "result" or more:
                raise Error("ideal helper return changed")
            index = tail
            continue
        index += 1


def _statement_start(data: Span[UInt8, _], index: Int) -> Bool:
    """Return whether `index` begins a statement.

    Args:
        data: The source bytes.
        index: The first byte of an identifier.

    Returns:
        True at the start of the text or after a newline and indentation.
    """
    var cursor = index
    while cursor > 0 and (data[cursor - 1] == 9 or data[cursor - 1] == 32):
        cursor -= 1
    if cursor == 0:
        return True
    return data[cursor - 1] == 10


def _call_argument(data: Span[UInt8, _], index: Int) -> Bool:
    """Return whether `index` is a positional call argument.

    Args:
        data: The source bytes.
        index: The start of an identifier.

    Returns:
        True when the previous non-space byte is `(` or `,`.
    """
    var cursor = index
    while cursor > 0 and _is_space_byte(data[cursor - 1]):
        cursor -= 1
    if cursor == 0:
        return False
    return data[cursor - 1] == 40 or data[cursor - 1] == 44


comptime _SUM2_IDEAL = """def _spiral_expression ( geometry : RoadGeometry , d : _JetExpression [ derivatives ] , pieces : Int , translation : Vector3 , ) -> Tuple [ _JetExpression [ derivatives ] , _JetExpression [ derivatives ] , _JetExpression [ derivatives ] , ] :
    Expression = _JetExpression [ derivatives ]
    if not _sum2_supported_environment ( ) :
        unknown = Expression ( _Interval . whole ( ) , _Interval . whole ( ) , _Interval . whole ( ) , inf [ DType . float64 ] ( ) , )
        return ( unknown , unknown , unknown )
    k0 = Expression . constant ( geometry . curvature_start )
    rate = Expression . constant ( ( geometry . curvature_end - geometry . curvature_start ) / geometry . length )
    step = d / Expression . constant ( Float64 ( pieces ) )
    nodes = materialize [ _GL_NODES ] ( )
    weights = materialize [ _GL_WEIGHTS ] ( )
    x = Expression . constant ( 0.0 )
    y = Expression . constant ( 0.0 )
    x_magnitude = _Interval . point ( 0.0 )
    y_magnitude = _Interval . point ( 0.0 )
    x_inherited = _Interval . point ( 0.0 )
    y_inherited = _Interval . point ( 0.0 )
    piece = 0
    while piece < pieces :
        start = step * Expression . constant ( Float64 ( piece ) )
        i = 0
        while i < 5 :
            t = start + _stored_half ( step ) * Expression . constant ( 1.0 + nodes [ i ] )
            theta = Expression . constant ( geometry . heading ) + t * ( k0 + _stored_half ( rate ) * t )
            trig = _sincos_expression ( theta )
            term_x = ( _stored_half ( step ) * Expression . constant ( weights [ i ] ) * trig [ 1 ] )
            term_y = ( _stored_half ( step ) * Expression . constant ( weights [ i ] ) * trig [ 0 ] )
            x = x + term_x
            y = y + term_y
            x_magnitude = x_magnitude + _Interval . point ( term_x . rounded_value ( ) . magnitude ( ) )
            y_magnitude = y_magnitude + _Interval . point ( term_y . rounded_value ( ) . magnitude ( ) )
            x_inherited = x_inherited + _Interval . point ( term_x . error )
            y_inherited = y_inherited + _Interval . point ( term_y . error )
            i += 1
        piece += 1
    x . error = _sum2_error_checked ( x_magnitude . high , x_inherited . high , 5 * pieces )
    y . error = _sum2_error_checked ( y_magnitude . high , y_inherited . high , 5 * pieces )
    heading = Expression . constant ( geometry . heading ) + d * ( k0 + _stored_half ( rate ) * d )
    return ( ( Expression . constant ( geometry . x ) - Expression . constant ( Float64 ( translation . x ) ) ) + x , ( Expression . constant ( geometry . y ) + Expression . constant ( Float64 ( translation . y ) ) ) + y , heading , )
"""

comptime _SUM2_PROJECTED = """def _spiral_expression ( geometry : RoadGeometry , d : _JetExpression [ derivatives ] , pieces : Int , translation : Vector3 , ) -> Tuple [ _JetExpression [ derivatives ] , _JetExpression [ derivatives ] , _JetExpression [ derivatives ] , ] :
    Expression = _JetExpression [ derivatives ]
    k0 = Expression . constant ( geometry . curvature_start )
    rate = Expression . constant ( ( geometry . curvature_end - geometry . curvature_start ) / geometry . length )
    step = d / Expression . constant ( Float64 ( pieces ) )
    nodes = materialize [ _GL_NODES ] ( )
    weights = materialize [ _GL_WEIGHTS ] ( )
    x = Expression . constant ( 0.0 )
    y = Expression . constant ( 0.0 )
    piece = 0
    while piece < pieces :
        start = step * Expression . constant ( Float64 ( piece ) )
        i = 0
        while i < 5 :
            t = start + _stored_half ( step ) * Expression . constant ( 1.0 + nodes [ i ] )
            theta = Expression . constant ( geometry . heading ) + t * ( k0 + _stored_half ( rate ) * t )
            trig = _sincos_expression ( theta )
            x = x + ( _stored_half ( step ) * Expression . constant ( weights [ i ] ) * trig [ 1 ] )
            y = y + ( _stored_half ( step ) * Expression . constant ( weights [ i ] ) * trig [ 0 ] )
            i += 1
        piece += 1
    heading = Expression . constant ( geometry . heading ) + d * ( k0 + _stored_half ( rate ) * d )
    return ( ( Expression . constant ( geometry . x ) - Expression . constant ( Float64 ( translation . x ) ) ) + x , ( Expression . constant ( geometry . y ) + Expression . constant ( Float64 ( translation . y ) ) ) + y , heading , )
"""


def _without_leading_newline(text: String) -> String:
    """Drop one leading newline from an embedded source string.

    Args:
        text: A source constant.

    Returns:
        `text` without a first newline, when it has one.
    """
    var data = text.as_bytes()
    var start = 0
    if len(data) > 0 and data[0] == 10:
        start = 1
    var out = String("")
    var index = start
    while index < len(data):
        out += chr(Int(data[index]))
        index += 1
    return out


def _rewrite_stored_half(text: String) raises -> String:
    """Rewrite each `_stored_half(name)` call into `name * half`.

    Args:
        text: Projected ideal source.

    Returns:
        JSON with the rewritten `source` and the call `arguments` in order.

    Raises:
        Error: A stored-half call is not one plain name.
    """
    var marker = "_stored_half ( "
    var data = text.as_bytes()
    var out = String("")
    var names = List[String]()
    var index = 0
    while index < len(data):
        if _starts_at(text, index, marker):
            var name_at = index + marker.byte_length()
            var name = _read_name(data, name_at)
            var after = name_at + name.byte_length()
            if name.byte_length() == 0 or not _starts_at(text, after, " )"):
                raise Error("unreviewed stored-half call shape")
            names.append(name)
            out += name
            out += " * Expression . constant ( 0.5 )"
            index = after + 2
        else:
            out += chr(Int(data[index]))
            index += 1
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "source", doc.new_str(out))
    var arguments = doc.new_list()
    for name in names:
        doc.append(arguments, doc.new_str(name))
    doc.set(root, "arguments", arguments)
    doc.root = root
    return doc.dumps()


def project_sum2_source(source: String) raises -> String:
    """Return the projected spiral and its stored-half arguments.

    Args:
        source: Mojo source that contains `def _spiral_expression[`.

    Returns:
        JSON with `source` and `arguments`. Each stored-half call is a product
        with one half.

    Raises:
        Error: The declaration is not the reviewed Sum2 ideal layout, or a
            stored-half call is not one plain name.
    """
    var normalized = ideal_function_source(source, "_spiral_expression")
    var expected = _without_leading_newline(_SUM2_IDEAL)
    var projected = _without_leading_newline(_SUM2_PROJECTED)
    if normalized != expected:
        raise Error("Sum2 complete ideal statement layout changed")
    return _rewrite_stored_half(projected)


def commute_legacy_source(source: String) raises -> String:
    """Swap each legacy half-rate product to rate times one half.

    Args:
        source: The historical ideal spiral source.

    Returns:
        JSON with the swapped `source` and the swap `count`.

    Raises:
        Error: The source is not the ideal spiral declaration.
    """
    var normalized = ideal_function_source(source, "_spiral_expression")
    var needle = "Expression . constant ( 0.5 ) * rate"
    var replacement = "rate * Expression . constant ( 0.5 )"
    var data = normalized.as_bytes()
    var out = String("")
    var count = 0
    var index = 0
    while index < len(data):
        if _starts_at(normalized, index, needle):
            out += replacement
            count += 1
            index += needle.byte_length()
        else:
            out += chr(Int(data[index]))
            index += 1
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "source", doc.new_str(out))
    doc.set(root, "count", doc.new_int(count))
    doc.root = root
    return doc.dumps()


def _store_operator(text: String) -> Bool:
    """Return whether `text` binds the name on its left.

    Args:
        text: One operator token.

    Returns:
        True for `=` and the augmented assignments, not for `==`.
    """
    if text == "=" or text == "+=" or text == "-=" or text == "*=":
        return True
    if text == "/=" or text == "%=" or text == "**=" or text == "//=":
        return True
    if text == "&=" or text == "|=" or text == "^=" or text == "<<=":
        return True
    if text == ">>=" or text == "@=":
        return True
    return False


def _binding_shadow(
    source: String,
    name: String,
    allowed: String,
    allow_definition: Bool,
) raises:
    """Reject a binding that shadows one reviewed helper name.

    Args:
        source: Mojo source to scan.
        name: The helper name that must not be shadowed.
        allowed: An import module that may bind `name`. Empty allows none.
        allow_definition: True when one function or struct of `name` is kept.

    Raises:
        Error: An import, declaration, assignment, parameter, or exception
            binds `name`.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var count = len(kinds)
    var index = 0
    var definitions = 0
    while index < count:
        if texts[index] == "from":
            var module = String("")
            index += 1
            while index < count and texts[index] != "import":
                if kinds[index] == _NAME or texts[index] == ".":
                    module += texts[index]
                index += 1
            if index < count and texts[index] == "import":
                index += 1
            var depth = 0
            while index < count:
                if texts[index] == "(":
                    depth += 1
                elif texts[index] == ")":
                    if depth > 0:
                        depth -= 1
                elif texts[index] == "*":
                    raise Error(
                        "wildcard import can shadow reviewed helper: " + name
                    )
                elif kinds[index] == _NAME and texts[index] != "as":
                    var bound = texts[index]
                    if (
                        index + 2 < count
                        and texts[index + 1] == "as"
                        and kinds[index + 2] == _NAME
                    ):
                        bound = texts[index + 2]
                        index += 2
                    if bound == name and module != allowed:
                        raise Error(
                            "reviewed helper import alias shadows: " + name
                        )
                elif texts[index] == "\n" and depth == 0:
                    break
                index += 1
        elif texts[index] == "import":
            index += 1
            while index < count and texts[index] != "\n":
                if kinds[index] == _NAME:
                    var bound = texts[index]
                    var dotted = False
                    while (
                        index + 2 < count
                        and texts[index + 1] == "."
                        and kinds[index + 2] == _NAME
                    ):
                        dotted = True
                        index += 2
                    if (
                        not dotted
                        and index + 2 < count
                        and texts[index + 1] == "as"
                        and kinds[index + 2] == _NAME
                    ):
                        bound = texts[index + 2]
                        index += 2
                    elif (
                        dotted
                        and index + 2 < count
                        and texts[index + 1] == "as"
                        and kinds[index + 2] == _NAME
                    ):
                        bound = texts[index + 2]
                        index += 2
                    if bound == name:
                        raise Error(
                            "reviewed helper module alias shadows: " + name
                        )
                index += 1
        elif (
            texts[index] == "def"
            or texts[index] == "struct"
            or texts[index] == "class"
        ):
            index += 1
            if index < count and kinds[index] == _NAME:
                if texts[index] == name:
                    definitions += 1
                    if not allow_definition or definitions > 1:
                        raise Error(
                            "reviewed helper declaration shadows: " + name
                        )
                index += 1
            if index < count and texts[index] == "[":
                var depth = 1
                index += 1
                while index < count and depth > 0:
                    if texts[index] == "[":
                        depth += 1
                    elif texts[index] == "]":
                        depth -= 1
                    index += 1
            if index < count and texts[index] == "(":
                var depth = 1
                var at_parameter = True
                index += 1
                while index < count and depth > 0:
                    if texts[index] == "(" or texts[index] == "[":
                        depth += 1
                        at_parameter = False
                    elif texts[index] == ")" or texts[index] == "]":
                        depth -= 1
                        at_parameter = depth == 1
                    elif texts[index] == ",":
                        at_parameter = depth == 1
                    elif (
                        at_parameter
                        and depth == 1
                        and kinds[index] == _NAME
                        and texts[index] == name
                    ):
                        raise Error(
                            "reviewed helper parameter shadows: " + name
                        )
                    elif texts[index] == ":" or texts[index] == "=":
                        at_parameter = False
                    index += 1
        elif texts[index] == "except":
            index += 1
            while index < count and texts[index] != "\n":
                if (
                    texts[index] == "as"
                    and index + 1 < count
                    and texts[index + 1] == name
                ):
                    raise Error(
                        "reviewed helper exception binding shadows: " + name
                    )
                index += 1
        elif (
            texts[index] == "var"
            and index + 1 < count
            and texts[index + 1] == name
        ):
            raise Error("reviewed helper assignment shadows: " + name)
        elif (
            texts[index] == "del"
            and index + 1 < count
            and texts[index + 1] == name
        ):
            raise Error("reviewed helper assignment shadows: " + name)
        elif (
            kinds[index] == _NAME and texts[index] == name and index + 1 < count
        ):
            if _store_operator(texts[index + 1]):
                raise Error("reviewed helper assignment shadows: " + name)
        index += 1


def _direct_imports_json(source: String) raises -> String:
    """Return the top-level `from` imports in source order.

    Args:
        source: Mojo source.

    Returns:
        A JSON list of `module` and `names`. Each name is `[name, alias]`.
        A relative prefix is omitted, matching Python `ImportFrom.module`.
        The alias is empty when the import does not rename it.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var count = len(kinds)
    var index = 0
    var indent = 0
    var doc = PyJson()
    var rows = doc.new_list()
    while index < count:
        if kinds[index] == _INDENT:
            indent += 1
        elif kinds[index] == _DEDENT:
            if indent > 0:
                indent -= 1
        elif indent == 0 and texts[index] == "from":
            var module = String("")
            var saw_import = False
            var saw_name = False
            index += 1
            while index < count and texts[index] != "import":
                if texts[index] == "." and not saw_name:
                    pass
                elif kinds[index] == _NAME or texts[index] == ".":
                    if kinds[index] == _NAME:
                        saw_name = True
                    module += texts[index]
                elif kinds[index] == _NEWLINE:
                    break
                index += 1
            var names = doc.new_list()
            if index < count and texts[index] == "import":
                saw_import = True
                index += 1
                var depth = 0
                while index < count:
                    if texts[index] == "(":
                        depth += 1
                    elif texts[index] == ")":
                        if depth > 0:
                            depth -= 1
                    elif kinds[index] == _NAME and texts[index] != "as":
                        var bound = texts[index]
                        var alias = String("")
                        if (
                            index + 2 < count
                            and texts[index + 1] == "as"
                            and kinds[index + 2] == _NAME
                        ):
                            alias = texts[index + 2]
                            index += 2
                        var pair = doc.new_list()
                        doc.append(pair, doc.new_str(bound))
                        doc.append(pair, doc.new_str(alias))
                        doc.append(names, pair)
                    elif kinds[index] == _NEWLINE and depth == 0:
                        break
                    index += 1
            if saw_import:
                var item = doc.new_dict()
                doc.set(item, "module", doc.new_str(module))
                doc.set(item, "names", names)
                doc.append(rows, item)
        index += 1
    doc.root = rows
    return doc.dumps()


def direct_imports_payload(payload: String) raises -> String:
    """Return the top-level `from` imports in one JSON document.

    Args:
        payload: JSON with `source`.

    Returns:
        A JSON list of module and name pairs.

    Raises:
        Error: The source cannot be tokenized.
    """
    var doc = PyJson.parse(payload)
    return _direct_imports_json(doc.text(doc.at(doc.root, "source")))


def binding_shadow_payload(payload: String) raises:
    """Reject a binding recorded in one JSON shadow document.

    Args:
        payload: JSON with `source`, `name`, `allowed`, and `allow_definition`.

    Raises:
        Error: The source binds `name` outside the allowed import or definition.
    """
    var doc = PyJson.parse(payload)
    var allow = doc.flag(doc.at(doc.root, "allow_definition"))
    _binding_shadow(
        doc.text(doc.at(doc.root, "source")),
        doc.text(doc.at(doc.root, "name")),
        doc.text(doc.at(doc.root, "allowed")),
        allow,
    )


def _starts_at(source: String, index: Int, prefix: String) -> Bool:
    """Return whether `source` has `prefix` at a byte index.

    Args:
        source: The text.
        index: The byte index.
        prefix: The ASCII prefix.

    Returns:
        True when the prefix fits and matches.
    """
    var data = source.as_bytes()
    var needle = prefix.as_bytes()
    if index < 0 or index + len(needle) > len(data):
        return False
    var cursor = 0
    while cursor < len(needle):
        if data[index + cursor] != needle[cursor]:
            return False
        cursor += 1
    return True


def function_slice(source: String, name: String) raises -> String:
    """Return one top-level function through the next `def` or decorator.

    Args:
        source: Mojo source.
        name: The function name.

    Returns:
        The source from `def NAME` through the line before the next top-level
        `def` or `@`. The slice runs to the end when no later marker exists.

    Raises:
        Error: The name is missing or occurs more than once.
    """
    var prefix = String("def ") + name
    var data = source.as_bytes()
    var starts = List[Int]()
    var ends = List[Int]()
    var index = 0
    var line_start = True
    while index < len(data):
        if line_start and _starts_at(source, index, prefix):
            var closer_at = index + prefix.byte_length()
            if closer_at < len(data):
                var closer = data[closer_at]
                if closer == 40 or closer == 91:
                    starts.append(index)
                    ends.append(closer_at + 1)
        if data[index] == 10:
            line_start = True
        else:
            line_start = False
        index += 1
    if len(starts) != 1:
        raise Error("missing or ambiguous function: " + name)
    var origin = ends[0]
    var relative = 0
    var at_line = True
    while origin + relative < len(data):
        if at_line and (
            _starts_at(source, origin + relative, "def ")
            or _starts_at(source, origin + relative, "@")
        ):
            return String(source[byte = starts[0] : origin + relative])
        if data[origin + relative] == 10:
            at_line = True
        else:
            at_line = False
        relative += 1
    return String(source[byte = starts[0] :])


def _code_at(kinds: List[Int], index: Int) -> Int:
    """Return the next token that is not a newline or indent.

    Args:
        kinds: The token kinds.
        index: The first token to inspect.

    Returns:
        The index of the next code token, or the end.
    """
    var cursor = index
    while cursor < len(kinds):
        var kind = kinds[cursor]
        if kind != _NEWLINE and kind != _INDENT and kind != _DEDENT:
            return cursor
        cursor += 1
    return cursor


def try_only_refusal(source: String) raises:
    """Require the lane proof to keep the reviewed try-only refusal.

    Args:
        source: Mojo source that contains `_lane_jet_model_proof`.

    Returns:
        Nothing.

    Raises:
        Error: The function is missing, or the try-only parameter, default,
            refusal, or flag use changed.
    """
    var slice = function_slice(source, "_lane_jet_model_proof")
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(slice, kinds, texts)
    var count = len(kinds)
    var index = _code_at(kinds, 0)
    if (
        index + 1 >= count
        or kinds[index] != _NAME
        or texts[index] != "def"
        or texts[index + 1] != "_lane_jet_model_proof"
    ):
        raise Error("missing or ambiguous function: _lane_jet_model_proof")
    index += 2
    if index < count and kinds[index] == _OP and texts[index] == "[":
        var depth = 1
        index += 1
        while index < count and depth > 0:
            if kinds[index] == _OP and texts[index] == "[":
                depth += 1
            elif kinds[index] == _OP and texts[index] == "]":
                depth -= 1
            index += 1
    index = _code_at(kinds, index)
    if index >= count or texts[index] != "(":
        raise Error("try-only parameter changed")
    index += 1
    var param_kinds = List[Int]()
    var param_texts = List[String]()
    var last_start = 0
    var pending = True
    var depth = 1
    while index < count and depth > 0:
        var kind = kinds[index]
        var text = texts[index]
        if kind == _OP and (text == "(" or text == "[" or text == "{"):
            depth += 1
        elif kind == _OP and (text == ")" or text == "]" or text == "}"):
            depth -= 1
            if depth == 0:
                index += 1
                break
        if depth == 1 and kind == _OP and text == ",":
            pending = True
            index += 1
            continue
        if kind == _NEWLINE or kind == _INDENT or kind == _DEDENT:
            index += 1
            continue
        if depth == 1 and pending:
            last_start = len(param_kinds)
            pending = False
        param_kinds.append(kind)
        param_texts.append(text)
        index += 1
    var length = len(param_kinds) - last_start
    var named = (
        length >= 3
        and param_kinds[last_start] == _NAME
        and param_texts[last_start] == "require_reuse"
        and param_kinds[last_start + 1] == _OP
        and param_texts[last_start + 1] == ":"
        and param_kinds[last_start + 2] == _NAME
        and param_texts[last_start + 2] == "Bool"
    )
    if not named:
        raise Error("try-only parameter changed")
    var default_false = (
        length == 5
        and param_texts[last_start + 3] == "="
        and param_texts[last_start + 4] == "False"
    )
    if not default_false:
        raise Error("try-only default must preserve historical callers")
    var header = 0
    while index < count:
        var kind = kinds[index]
        var text = texts[index]
        if kind == _OP and (text == "(" or text == "[" or text == "{"):
            header += 1
        elif kind == _OP and (text == ")" or text == "]" or text == "}"):
            if header > 0:
                header -= 1
        elif header == 0 and kind == _OP and text == ":":
            index += 1
            break
        index += 1
    var level = 0
    var matches = 0
    var saw_elif = False
    var refusal = False
    var names = 0
    while index < count:
        var kind = kinds[index]
        var text = texts[index]
        if kind == _INDENT:
            level += 1
            index += 1
            continue
        if kind == _DEDENT:
            if level > 0:
                level -= 1
            index += 1
            continue
        if kind == _NEWLINE:
            index += 1
            continue
        if kind == _NAME and text == "require_reuse":
            names += 1
        if (
            level == 1
            and kind == _NAME
            and text == "if"
            and index + 2 < count
            and texts[index + 1] == "reused"
            and texts[index + 2] == ":"
        ):
            matches += 1
            var cursor = index + 3
            var body_level = 1
            while cursor < count:
                var body_kind = kinds[cursor]
                if body_kind == _INDENT:
                    body_level += 1
                elif body_kind == _DEDENT:
                    if body_level > 0:
                        body_level -= 1
                elif (
                    body_level == 1
                    and body_kind != _NEWLINE
                    and body_kind != _INDENT
                    and body_kind != _DEDENT
                ):
                    break
                cursor += 1
            var elif_ok = (
                cursor + 2 < count
                and texts[cursor] == "elif"
                and texts[cursor + 1] == "require_reuse"
                and texts[cursor + 2] == ":"
            )
            if elif_ok:
                saw_elif = True
                var body = cursor + 3
                var inner = 1
                var words = List[String]()
                while body < count:
                    var body_kind = kinds[body]
                    if body_kind == _INDENT:
                        inner += 1
                    elif body_kind == _DEDENT:
                        if inner > 0:
                            inner -= 1
                        if inner == 0:
                            body += 1
                            break
                    elif (
                        inner == 2
                        and body_kind != _NEWLINE
                        and body_kind != _INDENT
                        and body_kind != _DEDENT
                    ):
                        words.append(texts[body])
                    elif (
                        inner == 1
                        and body_kind != _NEWLINE
                        and body_kind != _INDENT
                        and body_kind != _DEDENT
                    ):
                        break
                    body += 1
                var returned = (
                    len(words) == 4
                    and words[0] == "return"
                    and words[1] == "_unknown_point"
                    and words[2] == "("
                    and words[3] == ")"
                )
                var tail = _code_at(kinds, body)
                var followed = tail < count and (
                    texts[tail] == "else" or texts[tail] == "elif"
                )
                refusal = returned and followed
        index += 1
    if matches != 1 or not saw_elif:
        raise Error("try-only refusal missing from reuse/fallback edge")
    if not refusal:
        raise Error("try-only refusal changed")
    if names != 1:
        raise Error("try-only flag has an unreviewed use")


def python_syntax_json(source: String) raises -> String:
    """Return Python source and generic metadata for one Mojo fragment.

    Args:
        source: Mojo source to inspect as a Python AST.

    Returns:
        JSON with `source` and `generics`. `struct` is written as `class`.
        `var`, `mut`, `out`, `ref`, `comptime`, and `raises` are removed.

    Raises:
        Error: A generic declaration is unclosed or repeated, or the source
            cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var kept_kinds = List[Int]()
    var kept_texts = List[String]()
    var index = 0
    while index < len(kinds):
        var drop = kinds[index] == _NAME and (
            texts[index] == "var"
            or texts[index] == "mut"
            or texts[index] == "out"
            or texts[index] == "ref"
            or texts[index] == "comptime"
            or texts[index] == "raises"
        )
        if not drop:
            var word = texts[index]
            if kinds[index] == _NAME and word == "struct":
                word = "class"
            kept_kinds.append(kinds[index])
            kept_texts.append(word)
        index += 1
    var generic_kinds = List[String]()
    var generic_names = List[String]()
    var param_kinds = List[String]()
    var param_texts = List[String]()
    var param_starts = List[Int]()
    var param_counts = List[Int]()
    index = 0
    while index + 2 < len(kept_kinds):
        var opener = (
            kept_kinds[index] == _NAME
            and (kept_texts[index] == "def" or kept_texts[index] == "class")
            and kept_kinds[index + 1] == _NAME
            and kept_kinds[index + 2] == _OP
            and kept_texts[index + 2] == "["
        )
        if opener:
            var end = index + 3
            var depth = 1
            while end < len(kept_kinds) and depth > 0:
                if kept_texts[end] == "[":
                    depth += 1
                elif kept_texts[end] == "]":
                    depth -= 1
                end += 1
            if depth != 0:
                raise Error("unclosed Mojo generic declaration")
            var start = len(param_kinds)
            var token = index + 3
            while token < end - 1:
                if (
                    kept_kinds[token] != _NEWLINE
                    and kept_kinds[token] != _INDENT
                    and kept_kinds[token] != _DEDENT
                ):
                    param_kinds.append(_token_name(kept_kinds[token]))
                    param_texts.append(kept_texts[token])
                token += 1
            var count = len(param_kinds) - start
            if count > 0 and param_texts[start + count - 1] == ",":
                _ = param_kinds.pop()
                _ = param_texts.pop()
                count -= 1
            var key = kept_texts[index] + "\t" + kept_texts[index + 1]
            var seen = 0
            while seen < len(generic_kinds):
                var previous = generic_kinds[seen] + "\t" + generic_names[seen]
                if previous == key:
                    raise Error("ambiguous generic declaration")
                seen += 1
            generic_kinds.append(kept_texts[index])
            generic_names.append(kept_texts[index + 1])
            param_starts.append(start)
            param_counts.append(count)
            var next_kinds = List[Int]()
            var next_texts = List[String]()
            var copy = 0
            while copy < index + 2:
                next_kinds.append(kept_kinds[copy])
                next_texts.append(kept_texts[copy])
                copy += 1
            copy = end
            while copy < len(kept_kinds):
                next_kinds.append(kept_kinds[copy])
                next_texts.append(kept_texts[copy])
                copy += 1
            kept_kinds = next_kinds^
            kept_texts = next_texts^
        index += 1
    var out = String("")
    var indents = List[String]()
    indents.append("")
    var need_indent = False
    index = 0
    while index < len(kept_kinds):
        var kind = kept_kinds[index]
        if kind == _NEWLINE:
            out += "\n"
            need_indent = True
        elif kind == _DEDENT:
            if len(indents) > 1:
                _ = indents.pop()
        elif kind == _INDENT:
            indents.append(kept_texts[index])
        else:
            if need_indent:
                out += indents[len(indents) - 1]
                need_indent = False
            elif out.byte_length() > 0:
                var data = out.as_bytes()
                if data[len(data) - 1] != 10:
                    out += " "
            out += kept_texts[index]
        index += 1
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "source", doc.new_str(out))
    var rows = doc.new_list()
    var generic = 0
    while generic < len(generic_kinds):
        var entry = doc.new_list()
        var key = doc.new_list()
        doc.append(key, doc.new_str(generic_kinds[generic]))
        doc.append(key, doc.new_str(generic_names[generic]))
        doc.append(entry, key)
        var items = doc.new_list()
        var cursor = param_starts[generic]
        var count = param_counts[generic]
        var item = 0
        while item < count:
            var pair = doc.new_list()
            doc.append(pair, doc.new_str(param_kinds[cursor]))
            doc.append(pair, doc.new_str(param_texts[cursor]))
            doc.append(items, pair)
            cursor += 1
            item += 1
        doc.append(entry, items)
        doc.append(rows, entry)
        generic += 1
    doc.set(root, "generics", rows)
    doc.root = root
    return doc.dumps()


def _table_code(source: String) -> String:
    """Drop comments and join the table the way `str.splitlines` does.

    Args:
        source: The table source.

    Returns:
        The comment-free text, with surrounding whitespace removed.
    """
    var data = source.as_bytes()
    var joined = String("")
    var index = 0
    var first = True
    while index < len(data):
        var start = index
        var hash = -1
        while index < len(data) and data[index] != 10 and data[index] != 13:
            if hash < 0 and data[index] == 35:
                hash = index
            index += 1
        var end = index if hash < 0 else hash
        if not first:
            joined += "\n"
        first = False
        var cursor = start
        while cursor < end:
            joined += chr(Int(data[cursor]))
            cursor += 1
        if index < len(data) and data[index] == 13:
            index += 1
        if index < len(data) and data[index] == 10:
            index += 1
    var bytes = joined.as_bytes()
    var left = 0
    var right = len(bytes)
    while left < right and (
        bytes[left] == 9
        or bytes[left] == 10
        or bytes[left] == 11
        or bytes[left] == 12
        or bytes[left] == 13
        or bytes[left] == 32
    ):
        left += 1
    while right > left and (
        bytes[right - 1] == 9
        or bytes[right - 1] == 10
        or bytes[right - 1] == 11
        or bytes[right - 1] == 12
        or bytes[right - 1] == 13
        or bytes[right - 1] == 32
    ):
        right -= 1
    var out = String("")
    var copy = left
    while copy < right:
        out += chr(Int(bytes[copy]))
        copy += 1
    return out


def _hex_digit(byte: UInt8) -> Bool:
    """Return whether `byte` is a hexadecimal digit.

    Args:
        byte: One source byte.

    Returns:
        True for `0-9`, `a-f`, and `A-F`.
    """
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 70)
        or (byte >= 97 and byte <= 102)
    )


def _moment_word(text: String) -> Bool:
    """Return whether `text` is one `0x` word of 16 hex digits.

    Args:
        text: The candidate word.

    Returns:
        True when the spelling is `0x` plus 16 hexadecimal digits.
    """
    var data = text.as_bytes()
    if len(data) != 18 or data[0] != 48 or data[1] != 120:
        return False
    var index = 2
    while index < 18:
        if not _hex_digit(data[index]):
            return False
        index += 1
    return True


def moment_source(words_json: String) raises -> String:
    """Write the canonical stored-moment table.

    Args:
        words_json: A JSON list of 2816 `0x` words, low then high.

    Returns:
        The generated Mojo source, including the trailing newline.

    Raises:
        Error: The list is not 2816 hexadecimal words.
    """
    var doc = PyJson.parse(words_json)
    if doc.length(doc.root) != 2816:
        raise Error("malformed moment source word")
    var words = List[String]()
    var index = 0
    while index < 2816:
        var word = doc.text(doc.item(doc.root, index))
        if not _moment_word(word):
            raise Error("malformed moment source word")
        words.append(word)
        index += 1
    var out = String(
        "# Copyright (c) 2026 Seth Kitchen, PE\n"
        + "# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0\n"
        + "# GENERATED by tools/carla_lane_oracle/spiral_moments.py. Do not"
        " edit words.\n"
        + "# Replay: python3 -B tools/carla_lane_oracle/spiral_moments.py"
        " --check\n"
        + "# Proof and limits: tools/carla_lane_oracle/spiral-moments.md\n"
        + "# Exact stored GL/trig polynomial only; no fitted or ideal-sin/cos"
        " data.\n"
        + "# Layout: count 1..64; cosine 0..10 then sine 0..10; low then"
        " high.\n"
        + "# 64 * 22 * 2 UInt64 words = 22,528 raw payload bytes.\n"
        + "# Bound as ref global_constant[_SPIRAL_MOMENT_WORDS](), never"
        " materialize.\n"
        + "\n"
        + "comptime _SPIRAL_MOMENT_WORDS: Array[UInt64, 2816] = [\n"
    )
    var word = 0
    var count = 1
    while count <= 64:
        out += "    # Count " + String(count) + "\n"
        var side = 0
        while side < 2:
            if side == 0:
                out += "    # cosine\n"
            else:
                out += "    # sine\n"
            var coefficient = 0
            while coefficient < 11:
                out += "    UInt64(" + words[word] + "),\n"
                word += 1
                out += "    UInt64(" + words[word] + "),\n"
                word += 1
                coefficient += 1
            side += 1
        count += 1
    out += "]\n"
    return out


def moment_words_json(source: String, count: Int) raises -> String:
    """Return the hex words in the generated moment table.

    Args:
        source: The table source, already decoded as text.
        count: The required word count.

    Returns:
        A JSON list of `0x` words. Each word has 16 hexadecimal digits.

    Raises:
        Error: The declaration, its shape, or a word is malformed.
    """
    var code = _table_code(source)
    var data = code.as_bytes()
    var prefix = String(
        "comptime _SPIRAL_MOMENT_WORDS: Array[UInt64, "
    ).as_bytes()
    var index = 0
    var matched = len(data) >= len(prefix)
    while matched and index < len(prefix):
        if data[index] != prefix[index]:
            matched = False
        index += 1
    if not matched:
        raise Error("missing or malformed table declaration")
    var declared = 0
    var digits = 0
    while index < len(data) and data[index] >= 48 and data[index] <= 57:
        declared = declared * 10 + Int(data[index] - 48)
        digits += 1
        index += 1
        if digits > 9:
            raise Error("wrong table declaration shape")
    if digits == 0:
        raise Error("missing or malformed table declaration")
    var suffix = String("] = [").as_bytes()
    var cursor = 0
    var tail = index + len(suffix) < len(data)
    while tail and cursor < len(suffix):
        if data[index + cursor] != suffix[cursor]:
            tail = False
        cursor += 1
    if not tail or data[len(data) - 1] != 93:
        raise Error("missing or malformed table declaration")
    index += len(suffix)
    if declared != count:
        raise Error("wrong table declaration shape")
    var body_end = len(data) - 1
    var words = List[String]()
    while index < body_end:
        var byte = data[index]
        if (
            byte == 9
            or byte == 10
            or byte == 11
            or byte == 12
            or byte == 13
            or byte == 32
        ):
            index += 1
            continue
        var mark = String("UInt64(0x").as_bytes()
        var fit = index + len(mark) + 16 + 2 <= body_end
        var at = 0
        while fit and at < len(mark):
            if data[index + at] != mark[at]:
                fit = False
            at += 1
        var hex_at = 0
        while fit and hex_at < 16:
            if not _hex_digit(data[index + len(mark) + hex_at]):
                fit = False
            hex_at += 1
        var close_at = index + len(mark) + 16
        if fit and (data[close_at] != 41 or data[close_at + 1] != 44):
            fit = False
        if not fit:
            raise Error("malformed coefficient word or extra source")
        var word = String("0x")
        var hex_index = 0
        while hex_index < 16:
            word += chr(Int(data[index + len(mark) + hex_index]))
            hex_index += 1
        words.append(word)
        index = close_at + 2
    if len(words) != count:
        raise Error("missing or extra coefficient words")
    var doc = PyJson()
    var rows = doc.new_list()
    var word = 0
    while word < len(words):
        doc.append(rows, doc.new_str(words[word]))
        word += 1
    doc.root = rows
    return doc.dumps()


def _moment_value(text: String) raises -> UInt64:
    """Return the integer value of one `0x` moment word.

    Args:
        text: A `0x` word of 16 hexadecimal digits.

    Returns:
        The encoding.

    Raises:
        Error: The spelling is not one moment word.
    """
    if not _moment_word(text):
        raise Error("wrong derived table shape")
    var data = text.as_bytes()
    var value = UInt64(0)
    var index = 2
    while index < 18:
        var byte = data[index]
        var nibble = 0
        if byte >= 48 and byte <= 57:
            nibble = Int(byte) - 48
        elif byte >= 65 and byte <= 70:
            nibble = Int(byte) - 55
        else:
            nibble = Int(byte) - 87
        value = (value << 4) | UInt64(nibble)
        index += 1
    return value


def verify_moment_table(source: String, words_json: String) raises -> String:
    """Require the table to hold the derived words in canonical source.

    Args:
        source: The table source, already decoded as text.
        words_json: A JSON list of 2816 derived `0x` words.

    Returns:
        The JSON list of words read from `source`.

    Raises:
        Error: The declaration is malformed, a word differs, or the source
            is not the canonical generated text.
    """
    var parsed = moment_words_json(source, 2816)
    var expected = PyJson.parse(words_json)
    if expected.length(expected.root) != 2816:
        raise Error("wrong derived table shape")
    var actual = PyJson.parse(parsed)
    var index = 0
    while index < 2816:
        var found = _moment_value(actual.text(actual.item(actual.root, index)))
        var wanted = _moment_value(
            expected.text(expected.item(expected.root, index))
        )
        if found != wanted:
            raise Error("coefficient endpoint differs at word " + String(index))
        index += 1
    if moment_source(words_json) != source:
        raise Error("words match but source is not canonical generated bytes")
    return parsed


def moment_payload_json(words_json: String) raises -> String:
    """Return the big-endian payload and the canonical source digest.

    Args:
        words_json: A JSON list of 2816 `0x` words, low then high.

    Returns:
        JSON with `be64` hex, `be64_sha256`, `byte_count`, and
        `source_sha256`.

    Raises:
        Error: The list is not 2816 hexadecimal words.
    """
    var doc = PyJson.parse(words_json)
    if doc.length(doc.root) != 2816:
        raise Error("malformed moment source word")
    var packed = List[UInt8]()
    var index = 0
    while index < 2816:
        var text = doc.text(doc.item(doc.root, index))
        if not _moment_word(text):
            raise Error("malformed moment source word")
        var word = _moment_value(text)
        var shift = 56
        while shift >= 0:
            packed.append(UInt8(Int((word >> UInt64(shift)) & 0xFF)))
            shift -= 8
        index += 1
    var digits = "0123456789abcdef"
    var be64 = String("")
    var byte_index = 0
    while byte_index < len(packed):
        var byte = Int(packed[byte_index])
        be64 += String(digits[byte = byte >> 4 : (byte >> 4) + 1])
        be64 += String(digits[byte = byte & 15 : (byte & 15) + 1])
        byte_index += 1
    var source = moment_source(words_json)
    var out = PyJson()
    var payload = out.new_dict()
    out.set(payload, "be64", out.new_str(be64))
    out.set(payload, "be64_sha256", out.new_str(sha256_hex(Span(packed))))
    out.set(payload, "byte_count", out.new_int(len(packed)))
    out.set(
        payload, "source_sha256", out.new_str(sha256_hex(source.as_bytes()))
    )
    out.root = payload
    return out.dumps()


def normalized_block(source: String) -> String:
    """Drop comments and blank lines, and keep the remaining indentation.

    Args:
        source: A source block. A `#` starts a comment, including inside text.

    Returns:
        The kept lines, separated by newlines, with one final newline.
    """
    var data = source.as_bytes()
    var out = String("")
    var index = 0
    while index < len(data):
        var start = index
        var hash = -1
        while index < len(data) and data[index] != 10 and data[index] != 13:
            if hash < 0 and data[index] == 35:
                hash = index
            index += 1
        var end = index if hash < 0 else hash
        while end > start and (
            data[end - 1] == 9
            or data[end - 1] == 11
            or data[end - 1] == 12
            or data[end - 1] == 32
        ):
            end -= 1
        var left = start
        while left < end and (
            data[left] == 9
            or data[left] == 11
            or data[left] == 12
            or data[left] == 32
        ):
            left += 1
        if left < end:
            if out.byte_length() > 0:
                out += "\n"
            var cursor = start
            while cursor < end:
                out += chr(Int(data[cursor]))
                cursor += 1
        if index < len(data) and data[index] == 13:
            index += 1
        if index < len(data) and data[index] == 10:
            index += 1
    out += "\n"
    return out


def _locate(source: String, needle: String) -> Int:
    """Return the only match of `needle`, or -1.

    Args:
        source: The text to search.
        needle: The non-overlapping fragment.

    Returns:
        The byte index of the only match, or -1 when the count is not 1.
    """
    var data = source.as_bytes()
    var pattern = needle.as_bytes()
    if len(pattern) == 0:
        return -1
    var found = -1
    var index = 0
    while index + len(pattern) <= len(data):
        var same = True
        var cursor = 0
        while same and cursor < len(pattern):
            if data[index + cursor] != pattern[cursor]:
                same = False
            cursor += 1
        if same:
            if found >= 0:
                return -1
            found = index
            index += len(pattern)
        else:
            index += 1
    return found


def _line_number(source: String, offset: Int) -> Int:
    """Return the 1-based line of a byte offset.

    Args:
        source: The text.
        offset: The byte index.

    Returns:
        The line number, counting newline bytes before `offset`.
    """
    var data = source.as_bytes()
    var line = 1
    var index = 0
    var stop = offset
    if stop > len(data):
        stop = len(data)
    while index < stop:
        if data[index] == 10:
            line += 1
        index += 1
    return line


def _at_line_start(source: String, offset: Int) -> Bool:
    """Return whether `offset` is at the start of a line.

    Args:
        source: The text.
        offset: The byte index.

    Returns:
        True at offset 0 or immediately after a newline.
    """
    if offset == 0:
        return True
    return source.as_bytes()[offset - 1] == 10


def _has_top_level_line(doc: PyJson, line: Int) raises -> Bool:
    """Return whether a start record is `(line, 0)`.

    Args:
        doc: The JSON list of start pairs.
        line: The 1-based line.

    Returns:
        True when that line has a column-0 start.

    Raises:
        Error: A start pair is not a list.
    """
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var pair = doc.item(doc.root, index)
        if (
            doc.length(pair) >= 2
            and doc.text(doc.item(pair, 0)) == String(line)
            and doc.text(doc.item(pair, 1)) == "0"
        ):
            return True
        index += 1
    return False


def _last_normalized_line_is_decorator(text: String) -> Bool:
    """Return whether the last kept line starts with `@`.

    Args:
        text: One normalized block, ending in a newline.

    Returns:
        True when that line is a decorator.
    """
    var data = text.as_bytes()
    var end = len(data)
    if end > 0 and data[end - 1] == 10:
        end -= 1
    if end == 0:
        return False
    var start = end
    while start > 0 and data[start - 1] != 10:
        start -= 1
    return data[start] == 64


def _routing_token(
    doc: PyJson, row: Int, index: Int, kind: String, text: String
) raises -> Bool:
    """Return whether one routing pair is `kind` and `text`.

    Args:
        doc: The routing document.
        row: The statement list.
        index: The pair position.
        kind: The token kind name.
        text: The token text.

    Returns:
        True when the pair matches.

    Raises:
        Error: The pair is not a list.
    """
    var pair = doc.item(row, index)
    if doc.length(pair) < 2:
        return False
    return (
        doc.text(doc.item(pair, 0)) == kind
        and doc.text(doc.item(pair, 1)) == text
    )


def strip_try_only_routing(routing_json: String) raises -> String:
    """Remove the default-false `require_reuse` parameter from one declaration.

    Args:
        routing_json: The canonical routing JSON.

    Returns:
        The same JSON with that one parameter span removed.

    Raises:
        Error: The declaration is missing or repeated, or the parameter span
            is missing or repeated.
    """
    var doc = PyJson.parse(routing_json)
    var found = -1
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var row = doc.item(doc.root, index)
        if (
            doc.length(row) >= 2
            and _routing_token(doc, row, 0, "NAME", "def")
            and _routing_token(doc, row, 1, "NAME", "_lane_jet_model_proof")
        ):
            if found >= 0:
                raise Error("missing try-only routing declaration")
            found = index
        index += 1
    if found < 0:
        raise Error("missing try-only routing declaration")
    var row = doc.item(doc.root, found)
    var length = doc.length(row)
    var places = 0
    var at = -1
    index = 0
    while index + 6 <= length:
        if (
            _routing_token(doc, row, index, "NAME", "require_reuse")
            and _routing_token(doc, row, index + 1, "OP", ":")
            and _routing_token(doc, row, index + 2, "NAME", "Bool")
            and _routing_token(doc, row, index + 3, "OP", "=")
            and _routing_token(doc, row, index + 4, "NAME", "False")
            and _routing_token(doc, row, index + 5, "OP", ",")
        ):
            places += 1
            at = index
        index += 1
    if places != 1:
        raise Error("try-only routing parameter changed")
    var kept = doc.new_list()
    index = 0
    while index < length:
        if index == at:
            index += 6
            continue
        doc.append(kept, doc.item(row, index))
        index += 1
    doc.set_item(doc.root, found, kept)
    return doc.dumps()


def _pointer_key(doc: PyJson, pointer: Int) raises -> String:
    """Join one pointer into a single lookup key.

    Args:
        doc: The transition document.
        pointer: The pointer list.

    Returns:
        The parts separated by newlines.

    Raises:
        Error: A pointer part is not a string.
    """
    var key = String("")
    var count = doc.length(pointer)
    var index = 0
    while index < count:
        if index > 0:
            key += "\n"
        key += doc.text(doc.item(pointer, index))
        index += 1
    return key


def _pointer_value(doc: PyJson, pins: Int, pointer: Int) raises -> String:
    """Return the string at one pin pointer.

    Args:
        doc: The transition document.
        pins: The pin document.
        pointer: The pointer list.

    Returns:
        The current string at that pointer.

    Raises:
        Error: A pointer key is absent.
    """
    var node = pins
    var count = doc.length(pointer)
    var index = 0
    while index < count:
        node = doc.at(node, doc.text(doc.item(pointer, index)))
        index += 1
    return doc.text(node)


def pin_transition_rows(payload: String) raises -> String:
    """Return the current value at each coverage pin transition.

    Args:
        payload: JSON with `pins` and `transitions`.

    Returns:
        A JSON list of duplicate, actual, and expected rows.

    Raises:
        Error: A pointer key is absent.
    """
    var doc = PyJson.parse(payload)
    var pins = doc.at(doc.root, "pins")
    var transitions = doc.at(doc.root, "transitions")
    var rows = doc.new_list()
    var seen = List[String]()
    var count = doc.length(transitions)
    var index = 0
    while index < count:
        var change = doc.item(transitions, index)
        var pointer = doc.at(change, "pointer")
        var key = _pointer_key(doc, pointer)
        var duplicate = False
        var seen_index = 0
        while seen_index < len(seen):
            if seen[seen_index] == key:
                duplicate = True
            seen_index += 1
        var actual = String("")
        if not duplicate:
            actual = _pointer_value(doc, pins, pointer)
            seen.append(key)
        var row = doc.new_dict()
        doc.set(row, "duplicate", doc.new_bool(duplicate))
        doc.set(row, "actual", doc.new_str(actual))
        doc.set(row, "expected", doc.new_str(doc.text(doc.at(change, "after"))))
        doc.append(rows, row)
        index += 1
    doc.root = rows
    return doc.dumps()


def selected_block(source: String, begin: String, end: String) raises -> String:
    """Return one normalized source block between two markers.

    Args:
        source: The module source.
        begin: The opening marker. It must occur once.
        end: The closing marker. It must occur once, after `begin`.

    Returns:
        The normalized text from `begin` up to `end`.

    Raises:
        Error: A marker is missing, repeated, indented, or not a top-level
            token, or a decorator is attached to the opening line.
    """
    var start = _locate(source, begin)
    if start < 0:
        raise Error("missing or ambiguous source-block start")
    var stop = _locate(source, end)
    if stop < 0:
        raise Error("missing or ambiguous source-block end")
    if start >= stop:
        raise Error("moved source-block boundary")
    if not _at_line_start(source, start) or not _at_line_start(source, stop):
        raise Error("source-block boundary is not top-level")
    var starts = String("")
    try:
        starts = top_level_starts_json(source)
    except error:
        _ = String(error)
        raise Error("malformed source-block tokens")
    var doc = PyJson.parse(starts)
    if not _has_top_level_line(
        doc, _line_number(source, start)
    ) or not _has_top_level_line(doc, _line_number(source, stop)):
        raise Error("source-block boundary is not an actual top-level token")
    if _last_normalized_line_is_decorator(
        normalized_block(String(source[byte=:start]))
    ):
        raise Error("unbound decorator before source-block start")
    return normalized_block(String(source[byte=start:stop]))


def _decimal_literal(text: String) -> Bool:
    """Return whether `text` is one decimal literal.

    Args:
        text: The joined token text.

    Returns:
        True when the text matches the stored-constant spelling.
    """
    var data = text.as_bytes()
    var index = 0
    if len(data) == 0:
        return False
    if data[0] == 43 or data[0] == 45:
        index = 1
    if index >= len(data):
        return False
    if data[index] == 46:
        index += 1
        var start = index
        while index < len(data) and data[index] >= 48 and data[index] <= 57:
            index += 1
        if index == start:
            return False
    else:
        if data[index] < 48 or data[index] > 57:
            return False
        while index < len(data) and data[index] >= 48 and data[index] <= 57:
            index += 1
        if index < len(data) and data[index] == 46:
            index += 1
            while index < len(data) and data[index] >= 48 and data[index] <= 57:
                index += 1
    if index < len(data) and (data[index] == 101 or data[index] == 69):
        index += 1
        if index < len(data) and (data[index] == 43 or data[index] == 45):
            index += 1
        var exponent = index
        while index < len(data) and data[index] >= 48 and data[index] <= 57:
            index += 1
        if index == exponent:
            return False
    return index == len(data)


def _statement_token(
    doc: PyJson, statement: Int, index: Int, mut kind: String, mut text: String
) raises:
    """Read one `[kind, text]` pair.

    Args:
        doc: The statement document.
        statement: The statement list.
        index: The pair position.
        kind: The token kind name.
        text: The token text.

    Raises:
        Error: The pair is not a two-string list.
    """
    var pair = doc.item(statement, index)
    kind = doc.text(doc.item(pair, 0))
    text = doc.text(doc.item(pair, 1))


def _joined_literal(
    doc: PyJson, statement: Int, start: Int, end: Int, description: String
) raises -> String:
    """Return one signed decimal token span.

    Args:
        doc: The statement document.
        statement: The statement list.
        start: The first token.
        end: The token after the span.
        description: The failure name.

    Returns:
        The joined literal.

    Raises:
        Error: The span is not one decimal literal.
    """
    var count = end - start
    var kind = String("")
    var text = String("")
    var accepted = False
    if count == 1:
        _statement_token(doc, statement, start, kind, text)
        accepted = kind == "NUMBER"
    elif count == 2:
        _statement_token(doc, statement, start, kind, text)
        var second_kind = String("")
        var second_text = String("")
        _statement_token(doc, statement, start + 1, second_kind, second_text)
        accepted = (
            kind == "OP"
            and (text == "+" or text == "-")
            and second_kind == "NUMBER"
        )
        text += second_text
    if not accepted or not _decimal_literal(text):
        raise Error("unsupported " + description)
    return text


def constant_literals_json(
    source: String, name: String, kind: String, size: Int
) raises -> String:
    """Return the decimal literals of one top-level constant.

    Args:
        source: Mojo source.
        name: The constant name.
        kind: `array` or `scalar`.
        size: The array length. Scalar declarations ignore it.

    Returns:
        A JSON list of literal spellings.

    Raises:
        Error: The declaration is missing, ambiguous, or not one decimal list.
    """
    var raw = module_statements_json(source)
    var doc = PyJson.parse(raw)
    var matches = List[Int]()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var statement = doc.item(doc.root, index)
        if doc.length(statement) >= 2:
            var first_kind = String("")
            var first_text = String("")
            var second_kind = String("")
            var second_text = String("")
            _statement_token(doc, statement, 0, first_kind, first_text)
            _statement_token(doc, statement, 1, second_kind, second_text)
            if (
                first_kind == "NAME"
                and first_text == "comptime"
                and second_kind == "NAME"
                and second_text == name
            ):
                matches.append(index)
        index += 1
    var out = PyJson()
    var rows = out.new_list()
    if kind == "array":
        if len(matches) != 1:
            raise Error("missing or ambiguous constant array: " + name)
        var statement = doc.item(doc.root, matches[0])
        var length = doc.length(statement)
        var header = List[String]()
        header.append("NAME")
        header.append("comptime")
        header.append("NAME")
        header.append(name)
        header.append("OP")
        header.append(":")
        header.append("NAME")
        header.append("Array")
        header.append("OP")
        header.append("[")
        header.append("NAME")
        header.append("Float64")
        header.append("OP")
        header.append(",")
        header.append("NUMBER")
        header.append(String(size))
        header.append("OP")
        header.append("]")
        header.append("OP")
        header.append("=")
        header.append("OP")
        header.append("[")
        var same = length >= 12
        var cursor = 0
        while same and cursor < 11:
            var token_kind = String("")
            var token_text = String("")
            _statement_token(doc, statement, cursor, token_kind, token_text)
            if (
                token_kind != header[cursor * 2]
                or token_text != header[cursor * 2 + 1]
            ):
                same = False
            cursor += 1
        var last_kind = String("")
        var last_text = String("")
        if same:
            _statement_token(doc, statement, length - 1, last_kind, last_text)
            same = last_kind == "OP" and last_text == "]"
        if not same:
            raise Error(
                "unsupported complete constant-array declaration: " + name
            )
        var description = "constant literal: " + name
        var entry = 11
        var literal_count = 0
        var token = 11
        while token < length - 1:
            var token_kind = String("")
            var token_text = String("")
            _statement_token(doc, statement, token, token_kind, token_text)
            if token_kind == "OP" and token_text == ",":
                out.append(
                    rows,
                    out.new_str(
                        _joined_literal(
                            doc, statement, entry, token, description
                        )
                    ),
                )
                literal_count += 1
                entry = token + 1
            token += 1
        if entry < length - 1:
            out.append(
                rows,
                out.new_str(
                    _joined_literal(
                        doc, statement, entry, length - 1, description
                    )
                ),
            )
            literal_count += 1
        if literal_count != size:
            raise Error("wrong constant-array shape: " + name)
    else:
        if len(matches) != 1:
            raise Error("missing or ambiguous scalar: " + name)
        var statement = doc.item(doc.root, matches[0])
        var length = doc.length(statement)
        var expected = List[String]()
        expected.append("NAME")
        expected.append("comptime")
        expected.append("NAME")
        expected.append(name)
        expected.append("OP")
        expected.append("=")
        expected.append("NAME")
        expected.append("Float64")
        expected.append("OP")
        expected.append("(")
        var same = length >= 6
        var cursor = 0
        while same and cursor < 5:
            var token_kind = String("")
            var token_text = String("")
            _statement_token(doc, statement, cursor, token_kind, token_text)
            if (
                token_kind != expected[cursor * 2]
                or token_text != expected[cursor * 2 + 1]
            ):
                same = False
            cursor += 1
        var last_kind = String("")
        var last_text = String("")
        if same:
            _statement_token(doc, statement, length - 1, last_kind, last_text)
            same = last_kind == "OP" and last_text == ")"
        if not same:
            raise Error("unsupported complete scalar declaration: " + name)
        out.append(
            rows,
            out.new_str(
                _joined_literal(
                    doc,
                    statement,
                    5,
                    length - 1,
                    "scalar literal: " + name,
                )
            ),
        )
    out.root = rows
    return out.dumps()


def module_statements_json(source: String) raises -> String:
    """Return the top-level statements, without the module docstring.

    Args:
        source: Mojo source.

    Returns:
        The canonical JSON list of `[kind name, text]` statements.

    Raises:
        Error: The source routing is unsupported or incomplete.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    try:
        _tokenize(source, kinds, texts)
    except error:
        _ = String(error)
        raise Error("unsupported top-level source routing")
    var doc = PyJson()
    var rows = doc.new_list()
    var statement_kinds = List[Int]()
    var statement_texts = List[String]()
    var depth = 0
    var saw_statement = False
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        elif kind == _NEWLINE:
            if len(statement_kinds) > 0:
                var docstring = (
                    not saw_statement
                    and len(statement_kinds) == 1
                    and statement_kinds[0] == _STRING
                )
                if not docstring:
                    var statement = doc.new_list()
                    var token = 0
                    while token < len(statement_kinds):
                        var pair = doc.new_list()
                        doc.append(
                            pair,
                            doc.new_str(_token_name(statement_kinds[token])),
                        )
                        doc.append(pair, doc.new_str(statement_texts[token]))
                        doc.append(statement, pair)
                        token += 1
                    doc.append(rows, statement)
                saw_statement = True
                statement_kinds.clear()
                statement_texts.clear()
        elif depth == 0:
            statement_kinds.append(kind)
            statement_texts.append(texts[index])
        index += 1
    if len(statement_kinds) > 0 or depth != 0:
        raise Error("incomplete top-level source routing")
    doc.root = rows
    return doc.dumps()


def module_routing_json(source: String, constants: String) raises -> String:
    """Return top-level statements with stored-word bodies masked.

    Args:
        source: Mojo source.
        constants: A JSON list of comptime names whose right-hand sides are masked.

    Returns:
        The canonical routing document.

    Raises:
        Error: The source routing is unsupported, or a masked declaration has
            no equals sign.
    """
    var statements = PyJson.parse(module_statements_json(source))
    var names = PyJson.parse(constants)
    var doc = PyJson()
    var rows = doc.new_list()
    var count = statements.length(statements.root)
    var index = 0
    while index < count:
        var statement = statements.item(statements.root, index)
        var length = statements.length(statement)
        var const_name = String("")
        var equals = -1
        if length > 3:
            var first = statements.item(statement, 0)
            var second = statements.item(statement, 1)
            if (
                statements.text(statements.item(first, 0)) == "NAME"
                and statements.text(statements.item(first, 1)) == "comptime"
            ):
                const_name = statements.text(statements.item(second, 1))
                var name_index = 0
                var named = False
                while name_index < names.length(names.root):
                    if (
                        names.text(names.item(names.root, name_index))
                        == const_name
                    ):
                        named = True
                    name_index += 1
                if named:
                    var token = 0
                    while token < length:
                        var pair = statements.item(statement, token)
                        if (
                            statements.text(statements.item(pair, 0)) == "OP"
                            and statements.text(statements.item(pair, 1)) == "="
                        ):
                            equals = token
                            break
                        token += 1
                    if equals < 0:
                        raise Error("('OP', '=') is not in list")
        var out = doc.new_list()
        var limit = length
        if equals >= 0:
            limit = equals + 1
        var token = 0
        while token < limit:
            var pair = statements.item(statement, token)
            var copied = doc.new_list()
            doc.append(
                copied, doc.new_str(statements.text(statements.item(pair, 0)))
            )
            doc.append(
                copied, doc.new_str(statements.text(statements.item(pair, 1)))
            )
            doc.append(out, copied)
            token += 1
        if equals >= 0:
            var stored = doc.new_list()
            doc.append(stored, doc.new_str("STORED_WORDS"))
            doc.append(stored, doc.new_str(const_name))
            doc.append(out, stored)
        doc.append(rows, out)
        index += 1
    doc.root = rows
    return doc.dumps()


def top_level_starts_json(source: String) raises -> String:
    """Return the lines of top-level `def`, `from`, and `@` tokens.

    Args:
        source: Mojo source.

    Returns:
        A JSON list of `[line, 0]` pairs. Lines start at 1.

    Raises:
        Error: The source boundary tokens cannot be read.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    var lines = List[Int]()
    var start_cols = List[Int]()
    var token_end_lines = List[Int]()
    var end_cols = List[Int]()
    try:
        _tokenize_lines(
            source,
            kinds,
            texts,
            lines,
            start_cols,
            token_end_lines,
            end_cols,
        )
    except error:
        _ = String(error)
        raise Error("unsupported source-boundary tokens")
    var doc = PyJson()
    var rows = doc.new_list()
    var depth = 0
    var fresh = True
    var index = 0
    while index < len(kinds):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        elif kind == _NEWLINE:
            fresh = True
        else:
            if (
                depth == 0
                and fresh
                and (
                    texts[index] == "def"
                    or texts[index] == "from"
                    or texts[index] == "@"
                )
            ):
                var pair = doc.new_list()
                doc.append(pair, doc.new_int(lines[index]))
                doc.append(pair, doc.new_int(0))
                doc.append(rows, pair)
            fresh = False
        index += 1
    doc.root = rows
    return doc.dumps()


def token_words(source: String) raises -> List[String]:
    """Return the token texts, without layout tokens.

    Args:
        source: Mojo source.

    Returns:
        Names, numbers, strings and operators, in order.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var words = List[String]()
    for index in range(len(kinds)):
        var kind = kinds[index]
        if kind != _NEWLINE and kind != _INDENT and kind != _DEDENT:
            words.append(texts[index])
    return words^


def without_move_sigils(source: String) raises -> String:
    """Return `source` without a postfix `^` before `,` or `)`.

    Args:
        source: Mojo source, usually one declaration.

    Returns:
        A source Python's parser accepts as the same function.

    Raises:
        Error: A `^` is not immediately before `,` or `)`, or the source
            cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var kept_kinds = List[Int]()
    var kept_texts = List[String]()
    var index = 0
    while index < len(kinds):
        if kinds[index] == _OP and texts[index] == "^":
            var follow = index + 1
            if follow >= len(kinds) or (
                texts[follow] != "," and texts[follow] != ")"
            ):
                raise Error("unsupported move-token placement")
            index += 1
            continue
        kept_kinds.append(kinds[index])
        kept_texts.append(texts[index])
        index += 1
    var out = String("")
    index = 0
    while index < len(kept_kinds):
        var kind = kept_kinds[index]
        if kind == _NEWLINE:
            out += "\n"
        elif kind == _DEDENT:
            pass
        elif kind == _INDENT:
            out += kept_texts[index]
        else:
            if out.byte_length() > 0:
                var data = out.as_bytes()
                if data[len(data) - 1] != 10:
                    out += " "
            out += kept_texts[index]
        index += 1
    return out


def token_names(source: String) raises -> List[String]:
    """Return the NAME tokens of `source`, in order.

    Args:
        source: Mojo source.

    Returns:
        Each name, including keywords.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var names = List[String]()
    for index in range(len(kinds)):
        if kinds[index] == _NAME:
            names.append(texts[index])
    return names^


def _literal(kinds: List[Int], texts: List[String]) raises -> Float64:
    """Return one decimal literal.

    Args:
        kinds: The tokens of one array entry.
        texts: The token texts.

    Returns:
        The value, as Python `float` reads the spelling.

    Raises:
        Error: The entry is not one decimal number.
    """
    if len(kinds) == 0:
        raise Error("unsupported stored array literal")
    var spelling = texts[0]
    if len(kinds) == 1 and kinds[0] == _NUMBER:
        pass
    elif (
        len(kinds) == 2
        and kinds[0] == _OP
        and (texts[0] == "+" or texts[0] == "-")
        and kinds[1] == _NUMBER
    ):
        spelling = texts[0] + texts[1]
    else:
        raise Error("unsupported stored array literal")
    var index = 0
    var saw_digit = False
    var bytes = spelling.as_bytes()
    if len(bytes) > 0 and (bytes[0] == 43 or bytes[0] == 45):
        index = 1
    var dot = False
    var exponent = False
    while index < len(bytes):
        var byte = bytes[index]
        if byte >= 48 and byte <= 57:
            saw_digit = True
        elif byte == 46 and not dot and not exponent:
            dot = True
        elif (byte == 101 or byte == 69) and saw_digit and not exponent:
            exponent = True
            saw_digit = False
            if index + 1 < len(bytes) and (
                bytes[index + 1] == 43 or bytes[index + 1] == 45
            ):
                index += 1
        else:
            raise Error("unsupported stored array literal")
        index += 1
    if not saw_digit:
        raise Error("unsupported stored array literal")
    return parse_float(spelling)


def stored_float_array(
    source: String, name: String, size: Int
) raises -> List[Float64]:
    """Return one top-level `comptime` `Array[Float64, size]`.

    Args:
        source: Mojo source.
        name: The array name.
        size: The declared length.

    Returns:
        The stored values, in order.

    Raises:
        Error: The array is missing, repeated, or not a plain decimal list.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var depth = 0
    var part_kinds = List[Int]()
    var part_texts = List[String]()
    var values = List[Float64]()
    var hits = 0
    for index in range(len(kinds)):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
            continue
        if kind == _DEDENT:
            depth -= 1
            continue
        if kind == _NEWLINE:
            if (
                depth == 0
                and len(part_kinds) >= 2
                and part_kinds[0] == _NAME
                and part_texts[0] == "comptime"
                and part_kinds[1] == _NAME
                and part_texts[1] == name
            ):
                hits += 1
                if hits > 1:
                    raise Error("missing or ambiguous stored array: " + name)
                values = _array_values(part_kinds, part_texts, size)
            part_kinds.clear()
            part_texts.clear()
            continue
        part_kinds.append(kind)
        part_texts.append(texts[index])
    if hits != 1:
        raise Error("missing or ambiguous stored array: " + name)
    return values^


def _array_values(
    kinds: List[Int], texts: List[String], size: Int
) raises -> List[Float64]:
    """Return the decimals of one array statement.

    Args:
        kinds: The statement tokens.
        texts: The token texts.
        size: The declared length.

    Returns:
        The stored values.

    Raises:
        Error: The statement is not `Array[Float64, size] = [decimals]`.
    """
    var header = List[String]()
    header.append("comptime")
    header.append("")
    header.append(":")
    header.append("Array")
    header.append("[")
    header.append("Float64")
    header.append(",")
    header.append(String(size))
    header.append("]")
    header.append("=")
    header.append("[")
    var header_kinds = List[Int]()
    header_kinds.append(_NAME)
    header_kinds.append(_NAME)
    header_kinds.append(_OP)
    header_kinds.append(_NAME)
    header_kinds.append(_OP)
    header_kinds.append(_NAME)
    header_kinds.append(_OP)
    header_kinds.append(_NUMBER)
    header_kinds.append(_OP)
    header_kinds.append(_OP)
    header_kinds.append(_OP)
    if (
        len(kinds) < len(header_kinds) + 1
        or kinds[len(kinds) - 1] != _OP
        or texts[len(texts) - 1] != "]"
    ):
        raise Error("unsupported stored array")
    for index in range(len(header_kinds)):
        if kinds[index] != header_kinds[index]:
            raise Error("unsupported stored array")
        if index != 1 and texts[index] != header[index]:
            raise Error("unsupported stored array")
    var values = List[Float64]()
    var entry_kinds = List[Int]()
    var entry_texts = List[String]()
    for index in range(len(header_kinds), len(kinds) - 1):
        if kinds[index] == _OP and texts[index] == ",":
            values.append(_literal(entry_kinds, entry_texts))
            entry_kinds.clear()
            entry_texts.clear()
        else:
            entry_kinds.append(kinds[index])
            entry_texts.append(texts[index])
    if len(entry_kinds) > 0:
        values.append(_literal(entry_kinds, entry_texts))
    if len(values) != size:
        raise Error("unsupported stored array")
    return values^


def stored_scalar(source: String, name: String) raises -> Float64:
    """Return one top-level `comptime name = Float64(decimal)`.

    Args:
        source: Mojo source.
        name: The constant name.

    Returns:
        The stored value, as Python `float` reads the spelling.

    Raises:
        Error: The declaration is missing, repeated, or not one decimal.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var depth = 0
    var part_kinds = List[Int]()
    var part_texts = List[String]()
    var values = List[Float64]()
    for index in range(len(kinds)):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
            continue
        if kind == _DEDENT:
            depth -= 1
            continue
        if kind == _NEWLINE:
            if (
                depth == 0
                and len(part_kinds) >= 2
                and part_kinds[0] == _NAME
                and part_texts[0] == "comptime"
                and part_kinds[1] == _NAME
                and part_texts[1] == name
            ):
                if len(values) == 1:
                    raise Error("Missing or ambiguous selector constant")
                values.append(_scalar_value(part_kinds, part_texts, name))
            part_kinds.clear()
            part_texts.clear()
            continue
        part_kinds.append(kind)
        part_texts.append(texts[index])
    if len(values) != 1:
        raise Error("Missing or ambiguous selector constant")
    return values[0]


def _scalar_value(
    kinds: List[Int], texts: List[String], name: String
) raises -> Float64:
    """Return the decimal inside one `Float64` declaration.

    Args:
        kinds: The statement tokens.
        texts: The token texts.
        name: The constant name.

    Returns:
        The stored value.

    Raises:
        Error: The statement is not one decimal `Float64` call.
    """
    if len(kinds) < 6:
        raise Error("Unsupported complete selector constant declaration")
    var last = len(kinds) - 1
    var complete = (
        kinds[0] == _NAME
        and texts[0] == "comptime"
        and kinds[1] == _NAME
        and texts[1] == name
        and kinds[2] == _OP
        and texts[2] == "="
        and kinds[3] == _NAME
        and texts[3] == "Float64"
        and kinds[4] == _OP
        and texts[4] == "("
        and kinds[last] == _OP
        and texts[last] == ")"
    )
    if not complete:
        raise Error("Unsupported complete selector constant declaration")
    var entry_kinds = List[Int]()
    var entry_texts = List[String]()
    for index in range(5, last):
        entry_kinds.append(kinds[index])
        entry_texts.append(texts[index])
    try:
        return _literal(entry_kinds, entry_texts)
    except error:
        _ = String(error)
        raise Error("unsupported selector constant " + name)


def _word_text(values: List[Float64]) -> String:
    """Return the canonical JSON array of IEEE words.

    Args:
        values: The stored floats, in order.

    Returns:
        The decimal bit patterns, with no spaces.
    """
    var text = String("[")
    for index in range(len(values)):
        if index > 0:
            text += ", "
        text += String(bitcast[DType.uint64](values[index]))
    text += "]"
    return text


def _stored_words(source: String, name: String, size: Int) raises -> String:
    """Return the canonical words of one stored declaration.

    Args:
        source: Mojo source.
        name: The constant name.
        size: The array length, or 0 for one `Float64` scalar.

    Returns:
        The JSON array of IEEE words.

    Raises:
        Error: The declaration is missing, repeated, or not a plain decimal.
    """
    if size == 0:
        var one = List[Float64]()
        one.append(stored_scalar(source, name))
        return _word_text(one)
    return _word_text(stored_float_array(source, name, size))


def _append_token(mut doc: PyJson, rows: Int, kind: Int, text: String):
    """Append one `[kind, text]` pair.

    Args:
        doc: The token document.
        rows: The token list.
        kind: The Python token number.
        text: The token text.
    """
    var pair = doc.new_list()
    doc.append(pair, doc.new_int(kind))
    doc.append(pair, doc.new_str(text))
    doc.append(rows, pair)


def stored_word_document(
    source: String,
    array_names: List[String],
    array_sizes: List[Int],
    scalar_names: List[String],
) raises -> String:
    """Return the token list with stored declarations replaced by words.

    Args:
        source: Mojo source.
        array_names: The `Array[Float64, size]` names.
        array_sizes: The length of each array, in the same order.
        scalar_names: The `Float64` scalar names.

    Returns:
        The canonical JSON token list.

    Raises:
        Error: A stored declaration is missing, repeated, or not one decimal.
    """
    var names = List[String]()
    var payloads = List[String]()
    for index in range(len(array_names)):
        names.append(array_names[index])
        payloads.append(
            _stored_words(source, array_names[index], array_sizes[index])
        )
    for index in range(len(scalar_names)):
        names.append(scalar_names[index])
        payloads.append(_stored_words(source, scalar_names[index], 0))
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var doc = PyJson()
    var rows = doc.new_list()
    var depth = 0
    var part_kinds = List[Int]()
    var part_texts = List[String]()
    for index in range(len(kinds)):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        if kind == _NEWLINE:
            var lead = 0
            while lead < len(part_kinds) and part_kinds[lead] == _DEDENT:
                lead += 1
            var payload = -1
            if (
                depth == 0
                and len(part_kinds) >= lead + 2
                and part_kinds[lead] == _NAME
                and part_texts[lead] == "comptime"
                and part_kinds[lead + 1] == _NAME
            ):
                var declared = part_texts[lead + 1]
                for slot in range(len(names)):
                    if names[slot] == declared:
                        payload = slot
            if payload < 0:
                for slot in range(len(part_kinds)):
                    _append_token(doc, rows, part_kinds[slot], part_texts[slot])
            else:
                for slot in range(lead):
                    _append_token(doc, rows, part_kinds[slot], part_texts[slot])
                _append_token(doc, rows, _NAME, "STORED_WORD_DECLARATION")
                _append_token(doc, rows, _NAME, names[payload])
                _append_token(doc, rows, _STRING, payloads[payload])
            _append_token(doc, rows, _NEWLINE, texts[index])
            part_kinds.clear()
            part_texts.clear()
        else:
            part_kinds.append(kind)
            part_texts.append(texts[index])
    for slot in range(len(part_kinds)):
        _append_token(doc, rows, part_kinds[slot], part_texts[slot])
    doc.root = rows
    return doc.dumps()


def stored_word_sha256(
    source: String,
    array_names: List[String],
    array_sizes: List[Int],
    scalar_names: List[String],
) raises -> String:
    """Return the token digest with stored declarations replaced by words.

    Args:
        source: Mojo source.
        array_names: The `Array[Float64, size]` names.
        array_sizes: The length of each array, in the same order.
        scalar_names: The `Float64` scalar names.

    Returns:
        The hex digest of the canonical token list.

    Raises:
        Error: A stored declaration is missing, repeated, or not one decimal.
    """
    return sha256_hex(
        stored_word_document(
            source, array_names, array_sizes, scalar_names
        ).as_bytes()
    )


def def_token_sha256(source: String, name: String) raises -> String:
    """Return the token digest of one module-level function.

    Args:
        source: Mojo source.
        name: The function name.

    Returns:
        The hex digest of that function, including a preceding decorator.

    Raises:
        Error: The function is missing, repeated, or has no indented body.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var depth = 0
    var start_stmt = 0
    var decorator = -1
    var hits = 0
    var begin = 0
    var finish = 0
    for index in range(len(kinds)):
        var kind = kinds[index]
        if kind == _INDENT:
            depth += 1
        elif kind == _DEDENT:
            depth -= 1
        if kind != _NEWLINE:
            continue
        var lead = start_stmt
        while lead < index and kinds[lead] == _DEDENT:
            lead += 1
        var is_decorator = (
            lead < index and kinds[lead] == _OP and texts[lead] == "@"
        )
        var is_def = (
            lead + 1 < index
            and kinds[lead] == _NAME
            and texts[lead] == "def"
            and kinds[lead + 1] == _NAME
            and texts[lead + 1] == name
        )
        if depth == 0 and is_def:
            hits += 1
            if decorator >= 0:
                begin = decorator
            else:
                begin = lead
            var body = index + 1
            if body >= len(kinds) or kinds[body] != _INDENT:
                raise Error("unsupported function body: " + name)
            var nest = 0
            var end = body
            while end < len(kinds):
                if kinds[end] == _INDENT:
                    nest += 1
                elif kinds[end] == _DEDENT:
                    nest -= 1
                    if nest == 0:
                        finish = end + 1
                        break
                end += 1
            if nest != 0:
                raise Error("unclosed function body: " + name)
            decorator = -1
        elif depth == 0 and is_decorator:
            if decorator < 0:
                decorator = lead
        else:
            decorator = -1
        start_stmt = index + 1
    if hits != 1:
        raise Error("missing or ambiguous function: " + name)
    var doc = PyJson()
    var rows = doc.new_list()
    for index in range(begin, finish):
        _append_token(doc, rows, kinds[index], texts[index])
    doc.root = rows
    return sha256_hex(doc.dumps().as_bytes())
