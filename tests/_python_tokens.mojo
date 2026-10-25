# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Token digests that match CPython 3.12 `tokenize` for these Mojo sources."""

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
    mut kinds: List[Int], mut texts: List[String], kind: Int, var text: String
):
    """Append one token.

    Args:
        kinds: The token kinds.
        texts: The token texts, in the same order.
        kind: The Python token number.
        text: The token text.
    """
    kinds.append(kind)
    texts.append(text^)


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
    var text = source
    if not text.endswith("\n"):
        text += "\n"
    var data = text.as_bytes()
    var levels = List[Int]()
    levels.append(0)
    var index = 0
    var depth = 0
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
                _push(kinds, texts, _INDENT, spaces^)
                levels.append(column)
            else:
                while column < levels[len(levels) - 1]:
                    _ = levels.pop()
                    _push(kinds, texts, _DEDENT, String())
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
                continue
            if byte == 35 and depth == 0:
                while index < len(data) and data[index] != 10:
                    index += 1
                break
            if byte == 34 or byte == 39:
                var quote = byte
                var mark = index
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
                    index += 1
                if not closed:
                    raise Error("invalid source tokens: unclosed string")
                var literal = String(text[byte=mark:index])
                _push(kinds, texts, _STRING, literal^)
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
                _push(kinds, texts, _NAME, name^)
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
                                _push(kinds, texts, _NUMBER, prefixed^)
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
                _push(kinds, texts, _NUMBER, number^)
                continue
            var three = String()
            if index + 2 < len(data):
                three = String(text[byte = index : index + 3])
            if (
                three == "**="
                or three == "//="
                or three == "<<="
                or three == ">>="
            ):
                _push(kinds, texts, _OP, three^)
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
                _push(kinds, texts, _OP, two^)
                index += 2
                continue
            if byte == 40 or byte == 91 or byte == 123:
                depth += 1
            elif byte == 41 or byte == 93 or byte == 125:
                depth -= 1
                if depth < 0:
                    raise Error("invalid source tokens: extra closer")
            var operator = String(chr(Int(byte)))
            _push(kinds, texts, _OP, operator^)
            index += 1
        if index < len(data) and data[index] == 10:
            index += 1
            if depth == 0 and not blank:
                _push(kinds, texts, _NEWLINE, String("\n"))
    if depth != 0:
        raise Error("invalid source tokens: unclosed bracket")
    while len(levels) > 1:
        _ = levels.pop()
        _push(kinds, texts, _DEDENT, String())


def token_sha256(source: String) raises -> String:
    """Return the SHA-256 of the kept tokens, as CPython 3.12 does.

    Args:
        source: Mojo source.

    Returns:
        The hex digest of the canonical JSON token list.

    Raises:
        Error: The source cannot be tokenized.
    """
    var kinds = List[Int]()
    var texts = List[String]()
    _tokenize(source, kinds, texts)
    var doc = PyJson()
    var rows = doc.new_list()
    for index in range(len(kinds)):
        var pair = doc.new_list()
        doc.append(pair, doc.new_int(kinds[index]))
        doc.append(pair, doc.new_str(texts[index]))
        doc.append(rows, pair)
    doc.root = rows
    return sha256_hex(doc.dumps().as_bytes())


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
