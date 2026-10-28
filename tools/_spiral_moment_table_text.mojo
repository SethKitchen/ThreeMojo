# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read and rewrite the stored spiral-moment table declaration.

The reader returns the coefficient words in source order. The writer
rebuilds the canonical generated source from those words.
"""


comptime WORD_COUNT: Int = 2816
"""The number of coefficient words in the stored table."""


def _fail(message: String) raises:
    """Raise a table-declaration error.

    Args:
        message: The failure text.

    Raises:
        Error: The declaration check failed.
    """
    raise Error("spiral moment table: " + message)


def _is_space(byte: UInt8) -> Bool:
    """Return whether `byte` is ASCII whitespace.

    Args:
        byte: One source byte.

    Returns:
        True for tab, line feed, vertical tab, form feed, carriage
        return, and space.
    """
    if byte == 9:
        return True
    if byte == 10:
        return True
    if byte == 11:
        return True
    if byte == 12:
        return True
    if byte == 13:
        return True
    if byte == 32:
        return True
    return False


def _is_hex(byte: UInt8) -> Bool:
    """Return whether `byte` is an ASCII hexadecimal digit.

    Args:
        byte: One source byte.

    Returns:
        True for `0-9`, `A-F`, and `a-f`.
    """
    if byte >= 48 and byte <= 57:
        return True
    if byte >= 65 and byte <= 70:
        return True
    if byte >= 97 and byte <= 102:
        return True
    return False


def _hex_value(byte: UInt8) -> UInt64:
    """Return the value of one hexadecimal digit.

    Args:
        byte: An ASCII hexadecimal digit.

    Returns:
        The digit value, from 0 through 15.
    """
    if byte <= 57:
        return UInt64(byte) - 48
    if byte <= 70:
        return UInt64(byte) - 55
    return UInt64(byte) - 87


def _is_word_count(digits: String) -> Bool:
    """Return whether `digits` is the stored table length.

    Args:
        digits: The decimal length, with optional leading zeros.

    Returns:
        True when the value is 2816.
    """
    var raw = digits.as_bytes()
    var index = 0
    while index < len(raw):
        if raw[index] != 48:
            break
        index += 1
    var rest = digits[byte=index:]
    var tail = String(rest)
    return tail == "2816"


def _cut_comment(line: String) -> String:
    """Drop the first comment and everything after it.

    Args:
        line: One physical line, without its line ending.

    Returns:
        The line up to, and not including, the first `#`.
    """
    var raw = line.as_bytes()
    var index = 0
    while index < len(raw):
        if raw[index] == 35:
            var head = line[byte=0:index]
            return String(head)
        index += 1
    return line


def _strip(text: String) -> String:
    """Drop leading and trailing ASCII whitespace.

    Args:
        text: The comment-stripped source.

    Returns:
        The same text without outer whitespace.
    """
    var raw = text.as_bytes()
    var begin = 0
    var end = len(raw)
    while begin < end:
        if not _is_space(raw[begin]):
            break
        begin += 1
    while end > begin:
        if not _is_space(raw[end - 1]):
            break
        end -= 1
    var body = text[byte=begin:end]
    return String(body)


def _code(text: String) -> String:
    """Join the source with comments removed.

    Args:
        text: The decoded table source.

    Returns:
        The declaration text. Comments are gone and outer whitespace
        is gone.
    """
    var raw = text.as_bytes()
    var rows = List[String]()
    var start = 0
    var index = 0
    while index < len(raw):
        if raw[index] == 10:
            var piece = text[byte=start:index]
            rows.append(_cut_comment(String(piece)))
            start = index + 1
        index += 1
    var tail = text[byte=start:]
    rows.append(_cut_comment(String(tail)))
    var joined = String()
    var row = 0
    while row < len(rows):
        if row > 0:
            joined += "\n"
        joined += rows[row]
        row += 1
    return _strip(joined)


def _has(raw: Span[UInt8, _], index: Int, literal: String) -> Bool:
    """Return whether `literal` occurs at `index`.

    Args:
        raw: The declaration body.
        index: The first byte to compare.
        literal: The expected ASCII text.

    Returns:
        True when those bytes match.
    """
    var token = literal.as_bytes()
    if index + len(token) > len(raw):
        return False
    var offset = 0
    while offset < len(token):
        if raw[index + offset] != token[offset]:
            return False
        offset += 1
    return True


def _body(code: String) raises -> String:
    """Return the inside of a 2816-word table declaration.

    Args:
        code: Comment-stripped source.

    Returns:
        The bytes between the opening bracket and the final bracket.

    Raises:
        Error: The declaration is missing, malformed, or the wrong shape.
    """
    var prefix = "comptime _SPIRAL_MOMENT_WORDS: Array[UInt64, "
    if not code.startswith(prefix):
        _fail("missing or malformed table declaration")
    var raw = code.as_bytes()
    var index = prefix.byte_length()
    var digits = String()
    while index < len(raw):
        var byte = raw[index]
        if byte < 48 or byte > 57:
            break
        digits += chr(Int(byte))
        index += 1
    if digits.byte_length() == 0:
        _fail("missing or malformed table declaration")
    var marker = "] = ["
    if not _has(raw, index, marker):
        _fail("missing or malformed table declaration")
    if raw[len(raw) - 1] != 93:
        _fail("missing or malformed table declaration")
    if not _is_word_count(digits):
        _fail("wrong table declaration shape")
    var inner = code[byte = index + marker.byte_length() : len(raw) - 1]
    return String(inner)


def _words(body: String) raises -> List[UInt64]:
    """Return every `UInt64` word in `body`.

    Args:
        body: The bracket contents.

    Returns:
        The 2816 encodings, in source order.

    Raises:
        Error: A word is malformed, or the count is not 2816.
    """
    var raw = body.as_bytes()
    var words = List[UInt64]()
    var index = 0
    while index < len(raw):
        if _is_space(raw[index]):
            index += 1
            continue
        if not _has(raw, index, "UInt64(0x"):
            _fail("malformed coefficient word or extra source")
        index += 9
        if index + 18 > len(raw):
            _fail("malformed coefficient word or extra source")
        var word = UInt64(0)
        var digit = 0
        while digit < 16:
            var byte = raw[index]
            if not _is_hex(byte):
                _fail("malformed coefficient word or extra source")
            word = (word << 4) | _hex_value(byte)
            index += 1
            digit += 1
        if raw[index] != 41 or raw[index + 1] != 44:
            _fail("malformed coefficient word or extra source")
        index += 2
        words.append(word)
    if len(words) != WORD_COUNT:
        _fail("missing or extra coefficient words")
    return words^


def parse_table(data: Span[UInt8, _]) raises -> List[UInt64]:
    """Return the coefficient words in one table declaration.

    Args:
        data: UTF-8 source for the stored spiral-moment table.

    Returns:
        The 2816 coefficient encodings, in source order.

    Raises:
        Error: `data` is not UTF-8, the declaration is missing or
        malformed, the shape is not 2816, a word is malformed, or the
        word count is wrong.
    """
    var text = String("")
    var bad = False
    try:
        text = String(from_utf8=data)
    except e:
        bad = True
    if bad:
        _fail("table is not UTF-8")
    return _words(_body(_code(text)))


def _hex_word(word: UInt64) -> String:
    """Return `word` as `0x` and sixteen uppercase hexadecimal digits.

    Args:
        word: One coefficient encoding.

    Returns:
        The canonical literal.
    """
    var digits = "0123456789ABCDEF"
    var text = String("0x")
    var shift = 60
    while shift >= 0:
        var nibble = Int((word >> UInt64(shift)) & 15)
        var piece = digits[byte = nibble : nibble + 1]
        text += String(piece)
        shift -= 4
    return text


def canonical_table(words: List[UInt64]) raises -> String:
    """Return the canonical generated source for `words`.

    Args:
        words: The 2816 coefficient encodings, in source order.

    Returns:
        The generated table, including the fixed header.

    Raises:
        Error: `words` does not contain 2816 encodings.
    """
    if len(words) != WORD_COUNT:
        _fail("wrong derived table shape")
    var text = String(
        "# Copyright (c) 2026 Seth Kitchen, PE\n# SPDX-License-Identifier:"
        " PolyForm-Noncommercial-1.0.0\n# GENERATED by"
        " tools/spiral_moments.mojo. Do not edit words.\n#"
        " Check: mojo run -I . tools/spiral_moments.mojo --check\n#"
        " Exact stored GL/trig"
        " polynomial only; no fitted or ideal-sin/cos data.\n# Layout: count"
        " 1..64; cosine 0..10 then sine 0..10; low then high.\n# 64 * 22 * 2"
        " UInt64 words = 22,528 raw payload bytes.\n# Bound as ref"
        " global_constant[_SPIRAL_MOMENT_WORDS](), never"
        " materialize.\n\ncomptime _SPIRAL_MOMENT_WORDS: Array[UInt64, 2816]"
        " = [\n"
    )
    var cursor = 0
    var count = 1
    while count <= 64:
        text += "    # Count " + String(count) + "\n"
        var side = 0
        while side < 2:
            if side == 0:
                text += "    # cosine\n"
            else:
                text += "    # sine\n"
            var pair = 0
            while pair < 11:
                text += "    UInt64(" + _hex_word(words[cursor]) + "),\n"
                cursor += 1
                text += "    UInt64(" + _hex_word(words[cursor]) + "),\n"
                cursor += 1
                pair += 1
            side += 1
        count += 1
    text += "]\n"
    return text
