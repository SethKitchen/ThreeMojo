# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Project the top-level routing of a stored spiral module.

Function bodies stay out. A stored constant keeps its name and drops its
literal value. The initial module docstring stays out.
"""


def _fail(message: String) raises:
    """Raise a routing error.

    Args:
        message: The failure text.

    Raises:
        Error: The routing check failed.
    """
    raise Error("spiral moment routing: " + message)


def _is_stored(name: String) -> Bool:
    """Return whether `name` is a masked stored constant.

    Args:
        name: A top-level name.

    Returns:
        True for a stored array or scalar used by the spiral table.
    """
    if name == "_GL_NODES" or name == "_GL_WEIGHTS":
        return True
    if name == "_COS_COEFFICIENTS" or name == "_SIN_COEFFICIENTS":
        return True
    if name == "_PHASE_LIMIT" or name == "_INV_HALF_PI":
        return True
    if name == "_HALF_PI_HIGH" or name == "_HALF_PI_LOW":
        return True
    return False


def _json_string(text: String) -> String:
    """Return `text` as a compact JSON string.

    Args:
        text: A token spelling.

    Returns:
        The quoted JSON text.
    """
    var out = String('"')
    for byte in text.as_bytes():
        if byte == 34:
            out += '\\"'
        elif byte == 92:
            out += "\\\\"
        elif byte == 10:
            out += "\\n"
        elif byte == 13:
            out += "\\r"
        elif byte == 9:
            out += "\\t"
        elif byte == 8:
            out += "\\b"
        elif byte == 12:
            out += "\\f"
        elif byte < 32:
            var digits = "0123456789abcdef"
            var hi = Int(byte) // 16
            var lo = Int(byte) % 16
            out += "\\u00"
            out += String(digits[byte = hi : hi + 1])
            out += String(digits[byte = lo : lo + 1])
        else:
            out += chr(Int(byte))
    out += '"'
    return out


def _token_json(kind: String, text: String) -> String:
    """Return one `[kind, text]` JSON pair.

    Args:
        kind: The token kind.
        text: The token spelling.

    Returns:
        The compact JSON pair.
    """
    return "[" + _json_string(kind) + "," + _json_string(text) + "]"


def _name_end(data: Span[UInt8, _], index: Int) -> Int:
    """Return the byte after the identifier at `index`.

    Args:
        data: The source bytes.
        index: The first byte.

    Returns:
        The end index, or `index` when no identifier starts there.
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


def _number_end(data: Span[UInt8, _], index: Int) -> Int:
    """Return the byte after a number starting at `index`.

    Args:
        data: The source bytes.
        index: The first byte of a number.

    Returns:
        The end index. `index` means this byte is not a number.
    """
    if index >= len(data):
        return index
    var byte = data[index]
    var dotted = (
        byte == 46
        and index + 1 < len(data)
        and data[index + 1] >= 48
        and data[index + 1] <= 57
    )
    if not ((byte >= 48 and byte <= 57) or dotted):
        return index
    var mark = index
    var cursor = index
    if byte != 46:
        while cursor < len(data) and data[cursor] >= 48 and data[cursor] <= 57:
            cursor += 1
        if cursor == mark + 1 and data[mark] == 48 and cursor < len(data):
            var base = data[cursor]
            var based = (
                base == 120
                or base == 88
                or base == 98
                or base == 66
                or base == 111
                or base == 79
            )
            if based:
                var end = cursor + 1
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
                if end > cursor + 1:
                    return end
    if (
        cursor < len(data)
        and data[cursor] == 46
        and cursor + 1 < len(data)
        and data[cursor + 1] >= 48
        and data[cursor + 1] <= 57
    ):
        cursor += 1
        while cursor < len(data) and data[cursor] >= 48 and data[cursor] <= 57:
            cursor += 1
    if cursor < len(data) and (data[cursor] == 101 or data[cursor] == 69):
        var exponent = cursor + 1
        if exponent < len(data) and (
            data[exponent] == 43 or data[exponent] == 45
        ):
            exponent += 1
        if (
            exponent < len(data)
            and data[exponent] >= 48
            and data[exponent] <= 57
        ):
            cursor = exponent + 1
            while (
                cursor < len(data) and data[cursor] >= 48 and data[cursor] <= 57
            ):
                cursor += 1
    return cursor


def _three(text: String, index: Int) -> String:
    """Return three source bytes, or empty when they do not fit.

    Args:
        text: The source.
        index: The first byte.

    Returns:
        The three characters, or an empty string.
    """
    if index + 2 >= text.byte_length():
        return String()
    var piece = text[byte = index : index + 3]
    return String(piece)


def _two(text: String, index: Int) -> String:
    """Return two source bytes, or empty when they do not fit.

    Args:
        text: The source.
        index: The first byte.

    Returns:
        The two characters, or an empty string.
    """
    if index + 1 >= text.byte_length():
        return String()
    var piece = text[byte = index : index + 2]
    return String(piece)


def _is_three(text: String) -> Bool:
    """Return whether `text` is one three-character operator.

    Args:
        text: A three-byte slice.

    Returns:
        True for the reviewed assignment and ellipsis operators.
    """
    if text == "**=" or text == "//=" or text == "<<=":
        return True
    if text == ">>=" or text == "...":
        return True
    return False


def _is_two(text: String) -> Bool:
    """Return whether `text` is one two-character operator.

    Args:
        text: A two-byte slice.

    Returns:
        True for a reviewed two-character operator.
    """
    if text == "!=" or text == "+=" or text == "-=" or text == "*=":
        return True
    if text == "/=" or text == "%=" or text == "&=" or text == "|=":
        return True
    if text == "^=" or text == "<<" or text == ">>" or text == "->":
        return True
    if text == "<=" or text == ">=" or text == "==" or text == "//":
        return True
    return text == "**"


def _parameter_at(kinds: List[String], texts: List[String], index: Int) -> Bool:
    """Return whether the try-only parameter starts at `index`.

    Args:
        kinds: The statement token kinds.
        texts: The statement token spellings.
        index: The first token.

    Returns:
        True when the six tokens are the reviewed parameter.
    """
    if index + 6 > len(kinds):
        return False
    if kinds[index] != "NAME" or texts[index] != "require_reuse":
        return False
    if kinds[index + 1] != "OP" or texts[index + 1] != ":":
        return False
    if kinds[index + 2] != "NAME" or texts[index + 2] != "Bool":
        return False
    if kinds[index + 3] != "OP" or texts[index + 3] != "=":
        return False
    if kinds[index + 4] != "NAME" or texts[index + 4] != "False":
        return False
    if kinds[index + 5] != "OP" or texts[index + 5] != ",":
        return False
    return True


def _emit_statement(
    mut doc: String,
    mut started: Bool,
    mut emitted: Bool,
    kinds: List[String],
    texts: List[String],
    strip: Bool,
    mut definitions: Int,
) raises:
    """Append one top-level statement.

    Args:
        doc: The JSON document.
        started: True after the opening bracket.
        emitted: True after a statement is written.
        kinds: The statement token kinds.
        texts: The statement token spellings.
        strip: True when the try-only parameter is removed.
        definitions: The number of try-only declarations seen.

    Raises:
        Error: A stored declaration or the try-only parameter is unsupported.
    """
    if len(kinds) == 0:
        return
    if not emitted and len(kinds) == 1 and kinds[0] == "STRING":
        return
    var limit = len(kinds)
    var skip = -1
    var mask = -1
    if (
        len(kinds) > 3
        and kinds[0] == "NAME"
        and texts[0] == "comptime"
        and kinds[1] == "NAME"
        and _is_stored(texts[1])
    ):
        var index = 0
        while index < len(kinds):
            if kinds[index] == "OP" and texts[index] == "=":
                mask = index
                break
            index += 1
        if mask < 0:
            _fail("unsupported top-level source routing")
        limit = mask + 1
    elif (
        strip
        and len(kinds) > 1
        and kinds[0] == "NAME"
        and texts[0] == "def"
        and kinds[1] == "NAME"
        and texts[1] == "_lane_jet_model_proof"
    ):
        definitions += 1
        var index = 0
        var found = 0
        while index < len(kinds):
            if _parameter_at(kinds, texts, index):
                found += 1
                skip = index
            index += 1
        if found != 1:
            _fail("try-only routing parameter changed")
    if started:
        doc += ","
    started = True
    emitted = True
    doc += "["
    var first = True
    var index = 0
    while index < limit:
        if skip >= 0 and index >= skip and index < skip + 6:
            index += 1
            continue
        if not first:
            doc += ","
        first = False
        doc += _token_json(kinds[index], texts[index])
        index += 1
    if mask >= 0:
        if not first:
            doc += ","
        doc += _token_json("STORED_WORDS", texts[1])
    doc += "]"


def routing_json(source: String, strip_require_reuse: Bool) raises -> String:
    """Return the compact JSON routing projection of `source`.

    Args:
        source: Mojo source.
        strip_require_reuse: True when the try-only parameter is removed
            from `_lane_jet_model_proof`.

    Returns:
        The top-level statements. A stored constant ends at `STORED_WORDS`.

    Raises:
        Error: The source routing is incomplete, or the try-only parameter
        is missing.
    """
    var text = source
    if not text.endswith("\n"):
        text += "\n"
    var data = text.as_bytes()
    var levels = List[Int]()
    levels.append(0)
    var kinds = List[String]()
    var texts = List[String]()
    var doc = String("[")
    var started = False
    var emitted = False
    var definitions = 0
    var index = 0
    var bracket = 0
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
                        _fail("unsupported top-level source routing")
                if column != levels[len(levels) - 1]:
                    _fail("unsupported top-level source routing")
        while index < len(data):
            if data[index] == 10 and bracket == 0:
                break
            var byte = data[index]
            if byte == 32 or byte == 9:
                index += 1
                continue
            if byte == 10:
                index += 1
                continue
            if byte == 35:
                while index < len(data) and data[index] != 10:
                    index += 1
                if bracket == 0:
                    break
                continue
            var keep = len(levels) == 1
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
                        _fail("unsupported top-level source routing")
                    index += 1
                if not closed:
                    _fail("unsupported top-level source routing")
                if keep:
                    var literal = String(text[byte=mark:index])
                    kinds.append("STRING")
                    texts.append(literal)
                continue
            var name_end = _name_end(data, index)
            if name_end > index:
                if keep:
                    var name = String(text[byte=index:name_end])
                    kinds.append("NAME")
                    texts.append(name)
                index = name_end
                continue
            var number_end = _number_end(data, index)
            if number_end > index:
                if keep:
                    var number = String(text[byte=index:number_end])
                    kinds.append("NUMBER")
                    texts.append(number)
                index = number_end
                continue
            var three = _three(text, index)
            if _is_three(three):
                if keep:
                    kinds.append("OP")
                    texts.append(three)
                index += 3
                continue
            var two = _two(text, index)
            if _is_two(two):
                if keep:
                    kinds.append("OP")
                    texts.append(two)
                index += 2
                continue
            if byte == 40 or byte == 91 or byte == 123:
                bracket += 1
            elif byte == 41 or byte == 93 or byte == 125:
                bracket -= 1
                if bracket < 0:
                    _fail("unsupported top-level source routing")
            if keep:
                kinds.append("OP")
                texts.append(String(chr(Int(byte))))
            index += 1
        if index < len(data) and data[index] == 10:
            index += 1
            if bracket == 0 and not blank:
                _emit_statement(
                    doc,
                    started,
                    emitted,
                    kinds,
                    texts,
                    strip_require_reuse,
                    definitions,
                )
                kinds.clear()
                texts.clear()
    if bracket != 0 or len(kinds) != 0:
        _fail("incomplete top-level source routing")
    if strip_require_reuse and definitions != 1:
        _fail("missing try-only routing declaration")
    doc += "]"
    return doc
