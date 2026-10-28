# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Derive the fixed-count stored spiral-moment endpoints.

The nodes, weights, and trig coefficients are the stored binary64 words.
The moments share one unscaled prefix sum across the counts 1 through 64.
"""

from std.pathlib import Path

from tools._bigint import BigInt
from tools._cli_failures import derive_prefix
from tools._fraction import Fraction
from tools._payload_bytes import from_hex
from tools._python_json import PyJson
from tests._python_tokens import (
    moment_payload_json,
    moment_source,
    verify_moment_table,
)
from tools._spiral_moment_words import (
    bracket,
    decimal_word,
    fraction_of_word,
    hex_integers_json,
    hex_words_json,
    nearest_even,
)


def _fail(message: String) raises:
    """Raise a derivation error.

    Args:
        message: The failure text.

    Raises:
        Error: The derivation check failed.
    """
    raise Error(derive_prefix() + message)


def _is_name(byte: UInt8) -> Bool:
    """Return whether `byte` can continue an identifier.

    Args:
        byte: One source byte.

    Returns:
        True for ASCII letters, digits, and underscore.
    """
    if byte >= 65 and byte <= 90:
        return True
    if byte >= 97 and byte <= 122:
        return True
    if byte >= 48 and byte <= 57:
        return True
    return byte == 95


def _is_space(byte: UInt8) -> Bool:
    """Return whether `byte` is ASCII whitespace.

    Args:
        byte: One source byte.

    Returns:
        True for tab, line feed, vertical tab, form feed, carriage
        return, and space.
    """
    if byte == 9 or byte == 10 or byte == 11 or byte == 12:
        return True
    if byte == 13 or byte == 32:
        return True
    return False


def _mask(text: String) -> String:
    """Blank comments and string literals, keeping every other byte.

    Args:
        text: Mojo source.

    Returns:
        The same length, with comments and strings replaced by spaces.
    """
    var raw = text.as_bytes()
    var out = List[UInt8]()
    var index = 0
    while index < len(raw):
        var byte = raw[index]
        if index + 2 < len(raw) and (
            (byte == 34 and raw[index + 1] == 34 and raw[index + 2] == 34)
            or (byte == 39 and raw[index + 1] == 39 and raw[index + 2] == 39)
        ):
            var quote = byte
            var end = index + 3
            while end + 2 < len(raw):
                if (
                    raw[end] == quote
                    and raw[end + 1] == quote
                    and raw[end + 2] == quote
                ):
                    end += 3
                    break
                end += 1
            if end + 2 >= len(raw) and not (
                end >= 3
                and raw[end - 3] == quote
                and raw[end - 2] == quote
                and raw[end - 1] == quote
            ):
                end = len(raw)
            while index < end and index < len(raw):
                out.append(32)
                index += 1
            continue
        if byte == 34 or byte == 39:
            var quote = byte
            out.append(32)
            index += 1
            while index < len(raw):
                if raw[index] == 92:
                    out.append(32)
                    index += 1
                    if index < len(raw):
                        out.append(32)
                        index += 1
                    continue
                var done = raw[index] == quote
                out.append(32)
                index += 1
                if done:
                    break
            continue
        if byte == 35:
            while index < len(raw) and raw[index] != 10:
                out.append(32)
                index += 1
            continue
        out.append(byte)
        index += 1
    return String(unsafe_from_utf8=Span(out))


def _word_at(raw: Span[UInt8, _], index: Int, word: String) -> Bool:
    """Return whether `word` occurs as a whole identifier at `index`.

    Args:
        raw: The masked source.
        index: The first byte.
        word: The identifier.

    Returns:
        True when the bytes match and both sides are identifier boundaries.
    """
    var token = word.as_bytes()
    if index > 0 and _is_name(raw[index - 1]):
        return False
    if index + len(token) > len(raw):
        return False
    var offset = 0
    while offset < len(token):
        if raw[index + offset] != token[offset]:
            return False
        offset += 1
    var end = index + len(token)
    if end < len(raw) and _is_name(raw[end]):
        return False
    return True


def _skip_gaps(raw: Span[UInt8, _], index: Int) -> Int:
    """Skip spaces and tabs.

    Args:
        raw: The masked source.
        index: The first byte.

    Returns:
        The first byte that is not a space or a tab.
    """
    var cursor = index
    while cursor < len(raw):
        var byte = raw[cursor]
        if byte != 32 and byte != 9:
            break
        cursor += 1
    return cursor


def _skip_space(raw: Span[UInt8, _], index: Int) -> Int:
    """Skip ASCII whitespace.

    Args:
        raw: The masked source.
        index: The first byte.

    Returns:
        The first non-whitespace byte.
    """
    var cursor = index
    while cursor < len(raw) and _is_space(raw[cursor]):
        cursor += 1
    return cursor


def _eat(raw: Span[UInt8, _], index: Int, literal: String) -> Int:
    """Return the index after `literal`, or -1 when it is absent.

    Args:
        raw: The masked source.
        index: The first byte.
        literal: The expected ASCII text.

    Returns:
        The index after the literal, or -1.
    """
    var token = literal.as_bytes()
    if index + len(token) > len(raw):
        return -1
    var offset = 0
    while offset < len(token):
        if raw[index + offset] != token[offset]:
            return -1
        offset += 1
    return index + len(token)


def _body_at(raw: Span[UInt8, _], start: Int, name: String, size: Int) -> Int:
    """Return the index of the array body, or a negative status.

    Args:
        raw: The masked source.
        start: The `comptime` identifier.
        name: The array name.
        size: The declared length.

    Returns:
        The index after the opening value bracket. -1 means another
        name. -2 means this name is not the expected declaration.
    """
    var index = _skip_gaps(raw, start + 8)
    if not _word_at(raw, index, name):
        return -1
    index = _skip_gaps(raw, index + name.byte_length())
    index = _eat(raw, index, ":")
    if index < 0:
        return -2
    index = _eat(raw, _skip_gaps(raw, index), "Array")
    if index < 0:
        return -2
    index = _eat(raw, _skip_gaps(raw, index), "[")
    if index < 0:
        return -2
    index = _eat(raw, _skip_gaps(raw, index), "Float64")
    if index < 0:
        return -2
    index = _eat(raw, _skip_gaps(raw, index), ",")
    if index < 0:
        return -2
    index = _skip_gaps(raw, index)
    var digits = String(size)
    index = _eat(raw, index, digits)
    if index < 0:
        return -2
    if index < len(raw) and raw[index] >= 48 and raw[index] <= 57:
        return -2
    index = _eat(raw, _skip_gaps(raw, index), "]")
    if index < 0:
        return -2
    index = _eat(raw, _skip_gaps(raw, index), "=")
    if index < 0:
        return -2
    index = _eat(raw, _skip_gaps(raw, index), "[")
    if index < 0:
        return -2
    return index


def _read_literal(raw: Span[UInt8, _], start: Int) raises -> Tuple[String, Int]:
    """Read one decimal literal.

    Args:
        raw: The masked source.
        start: The first byte of the literal.

    Returns:
        The spelling and the index after it.

    Raises:
        Error: The bytes are not one decimal literal.
    """
    var index = start
    if index >= len(raw):
        _fail("unsupported constant literal")
    var spelling = String()
    var byte = raw[index]
    if byte == 43 or byte == 45:
        spelling += chr(Int(byte))
        index += 1
        index = _skip_space(raw, index)
    if index >= len(raw):
        _fail("unsupported constant literal")
    var saw_digit = False
    if raw[index] == 46:
        spelling += "."
        index += 1
        if index >= len(raw) or raw[index] < 48 or raw[index] > 57:
            _fail("unsupported constant literal")
        while index < len(raw) and raw[index] >= 48 and raw[index] <= 57:
            spelling += chr(Int(raw[index]))
            saw_digit = True
            index += 1
    else:
        if raw[index] < 48 or raw[index] > 57:
            _fail("unsupported constant literal")
        while index < len(raw) and raw[index] >= 48 and raw[index] <= 57:
            spelling += chr(Int(raw[index]))
            saw_digit = True
            index += 1
        if index < len(raw) and raw[index] == 46:
            spelling += "."
            index += 1
            while index < len(raw) and raw[index] >= 48 and raw[index] <= 57:
                spelling += chr(Int(raw[index]))
                index += 1
    if not saw_digit:
        _fail("unsupported constant literal")
    if index < len(raw) and (raw[index] == 101 or raw[index] == 69):
        spelling += chr(Int(raw[index]))
        index += 1
        if index < len(raw) and (raw[index] == 43 or raw[index] == 45):
            spelling += chr(Int(raw[index]))
            index += 1
        var saw_exp = False
        while index < len(raw) and raw[index] >= 48 and raw[index] <= 57:
            spelling += chr(Int(raw[index]))
            saw_exp = True
            index += 1
        if not saw_exp:
            _fail("unsupported constant literal")
    return (spelling, index)


def _suffix_clear(raw: Span[UInt8, _], start: Int) -> Bool:
    """Return whether the declaration ends at `start`.

    Args:
        raw: The masked source.
        start: The byte after the closing bracket.

    Returns:
        True when only whitespace and line continuations remain on the
        statement.
    """
    var index = start
    while index < len(raw):
        var byte = raw[index]
        if byte == 32 or byte == 9:
            index += 1
            continue
        if byte == 10 or byte == 13:
            return True
        if byte == 92:
            index += 1
            if index < len(raw) and raw[index] == 13:
                index += 1
                if index < len(raw) and raw[index] == 10:
                    index += 1
                continue
            if index < len(raw) and raw[index] == 10:
                index += 1
                continue
        return False
    return True


def _literals(
    raw: Span[UInt8, _], start: Int, size: Int
) raises -> List[String]:
    """Return the decimal spellings in one array body.

    Args:
        raw: The masked source.
        start: The first byte inside the value brackets.
        size: The declared length.

    Returns:
        The literal spellings, in order.

    Raises:
        Error: A literal, the suffix, or the length is unsupported.
    """
    var values = List[String]()
    var index = start
    while True:
        index = _skip_space(raw, index)
        if index >= len(raw):
            _fail("unsupported constant array")
        if raw[index] == 93:
            if not _suffix_clear(raw, index + 1):
                _fail("unsupported constant array")
            break
        var literal = _read_literal(raw, index)
        values.append(literal[0])
        index = _skip_space(raw, literal[1])
        if index >= len(raw):
            _fail("unsupported constant array")
        if raw[index] == 44:
            index += 1
            continue
        if raw[index] == 93:
            if not _suffix_clear(raw, index + 1):
                _fail("unsupported constant array")
            break
        _fail("unsupported constant literal")
    if len(values) != size:
        _fail("wrong constant-array shape")
    return values^


def stored_coefficient_words(
    source: String, name: String, size: Int
) raises -> List[UInt64]:
    """Return the stored binary64 words of one constant array.

    Args:
        source: Mojo source.
        name: The `comptime` array name.
        size: The declared length.

    Returns:
        The nearest encodings of the decimal literals, in order.
        `-0.0` keeps its sign.

    Raises:
        Error: The array is missing, repeated, or not a plain decimal list.
    """
    var masked = _mask(source)
    var raw = masked.as_bytes()
    var bodies = List[Int]()
    var bad = False
    var index = 0
    while index < len(raw):
        if _word_at(raw, index, "comptime"):
            var body = _body_at(raw, index, name, size)
            if body == -2:
                bad = True
            elif body >= 0:
                bodies.append(body)
            index += 8
            continue
        index += 1
    if len(bodies) > 1 or (len(bodies) == 1 and bad):
        _fail("missing or ambiguous constant array: " + name)
    if len(bodies) == 0:
        if bad:
            _fail("unsupported constant array: " + name)
        _fail("missing or ambiguous constant array: " + name)
    var spellings = _literals(raw, bodies[0], size)
    var words = List[UInt64]()
    for spelling in spellings:
        words.append(decimal_word(spelling))
    return words^


def _scalar_word_at(
    raw: Span[UInt8, _], start: Int, name: String
) raises -> Tuple[Int, UInt64]:
    """Return one scalar word at a `comptime` declaration.

    Args:
        raw: The masked source.
        start: The `comptime` identifier.
        name: The scalar name.

    Returns:
        A status and a word. Status -1 is another name, -2 is a bad
        declaration of `name`, and 0 is a stored word.

    Raises:
        Error: The literal is not a decimal number.
    """
    var index = _skip_gaps(raw, start + 8)
    if not _word_at(raw, index, name):
        return (-1, UInt64(0))
    index = _skip_gaps(raw, index + name.byte_length())
    index = _eat(raw, index, "=")
    if index < 0:
        return (-2, UInt64(0))
    index = _eat(raw, _skip_gaps(raw, index), "Float64")
    if index < 0:
        return (-2, UInt64(0))
    index = _eat(raw, _skip_gaps(raw, index), "(")
    if index < 0:
        return (-2, UInt64(0))
    index = _skip_space(raw, index)
    var literal = _read_literal(raw, index)
    index = _skip_space(raw, literal[1])
    if index >= len(raw) or raw[index] != 41:
        return (-2, UInt64(0))
    if not _suffix_clear(raw, index + 1):
        return (-2, UInt64(0))
    return (0, decimal_word(literal[0]))


def stored_scalar_word(source: String, name: String) raises -> UInt64:
    """Return the stored binary64 word of one scalar constant.

    Args:
        source: Mojo source.
        name: The `comptime` scalar name.

    Returns:
        The nearest encoding of the decimal literal. `-0.0` keeps its sign.

    Raises:
        Error: The scalar is missing, repeated, or not one `Float64` literal.
    """
    var masked = _mask(source)
    var raw = masked.as_bytes()
    var hits = 0
    var bad = False
    var word = UInt64(0)
    var index = 0
    while index < len(raw):
        if _word_at(raw, index, "comptime"):
            var parsed = _scalar_word_at(raw, index, name)
            if parsed[0] == -2:
                bad = True
            elif parsed[0] == 0:
                hits += 1
                word = parsed[1]
            index += 8
            continue
        index += 1
    if hits > 1 or (hits == 1 and bad):
        _fail("missing or ambiguous scalar: " + name)
    if hits == 0:
        if bad:
            _fail("unsupported scalar declaration: " + name)
        _fail("missing or ambiguous scalar: " + name)
    return word


def _moment(sum: Fraction, index: Int, count: Int) raises -> Fraction:
    """Return one normalized prefix moment.

    Args:
        sum: The unscaled prefix sum.
        index: The power index, from 0 through 21.
        count: The sample count, from 1 through 64.

    Returns:
        `sum / (2 * count ** (2 * index + 1))`.
    """
    var divisor = BigInt(2) * (BigInt(count) ** (2 * index + 1))
    return sum / Fraction(divisor)


def _fraction_text(value: Fraction) -> String:
    """Return `n/d`, or `n` when the denominator is one.

    Args:
        value: The exact coefficient.

    Returns:
        The text `str(Fraction)` would produce.
    """
    var text = value.numerator.to_string()
    if value.denominator != BigInt(1):
        text += "/"
        text += value.denominator.to_string()
    return text


def _append_side(
    mut words: List[UInt64],
    coefficients: List[Fraction],
    sums: List[Fraction],
    parity: Int,
    count: Int,
    mut exacts: List[String],
    keep_exact: Bool,
) raises:
    """Append one side's tight endpoints.

    Args:
        words: The destination encodings.
        coefficients: The cosine or sine coefficients.
        sums: The 22 unscaled prefix sums.
        parity: 0 for cosine and 1 for sine.
        count: The sample count.
        exacts: The exact spellings, when `keep_exact` is true.
        keep_exact: True when the caller records each exact value.

    Raises:
        Error: An endpoint does not fit in binary64.
    """
    var index = 0
    while index < len(coefficients):
        var exact = coefficients[index] * _moment(
            sums[2 * index + parity], 2 * index + parity, count
        )
        if keep_exact:
            exacts.append(_fraction_text(exact))
        var pair = bracket(exact)
        words.append(pair[0])
        words.append(pair[1])
        index += 1


def _derive_words(
    nodes: List[UInt64],
    weights: List[UInt64],
    cosine: List[UInt64],
    sine: List[UInt64],
    mut exacts: List[String],
    keep_exact: Bool,
) raises -> List[UInt64]:
    """Return the 2816 tight endpoints for counts 1 through 64.

    Args:
        nodes: The five stored Gauss-Legendre nodes.
        weights: The five stored Gauss-Legendre weights.
        cosine: The eleven stored cosine coefficients.
        sine: The eleven stored sine coefficients.
        exacts: The exact spellings, when `keep_exact` is true.
        keep_exact: True when each exact coefficient is recorded.

    Returns:
        Low then high for cosine 0 through 10, then sine 0 through 10,
        for each count from 1 through 64.

    Raises:
        Error: A list has the wrong length, the zeroth moment drifts,
        or an endpoint does not fit in binary64.
    """
    if len(nodes) != 5 or len(weights) != 5:
        _fail("wrong constant-array shape")
    if len(cosine) != 11 or len(sine) != 11:
        _fail("wrong constant-array shape")
    var node_sums = List[Fraction]()
    for node in nodes:
        var rounded = nearest_even(Fraction(1) + fraction_of_word(node))
        node_sums.append(fraction_of_word(rounded))
    var weight_values = List[Fraction]()
    for weight in weights:
        weight_values.append(fraction_of_word(weight))
    var cosine_values = List[Fraction]()
    for coefficient in cosine:
        cosine_values.append(fraction_of_word(coefficient))
    var sine_values = List[Fraction]()
    for coefficient in sine:
        sine_values.append(fraction_of_word(coefficient))
    var sums = List[Fraction]()
    var index = 0
    while index < 22:
        sums.append(Fraction(0))
        index += 1
    var zeroth = Fraction(1) + Fraction.of(BigInt(3), BigInt.power_of_two(55))
    var words = List[UInt64]()
    var count = 1
    while count <= 64:
        var node_index = 0
        while node_index < 5:
            var base = Fraction(count - 1) + (
                node_sums[node_index] / Fraction(2)
            )
            var square = base**2
            var power = Fraction(1)
            var power_index = 0
            while power_index < 22:
                sums[power_index] = sums[power_index] + (
                    weight_values[node_index] * power
                )
                power = power * square
                power_index += 1
            node_index += 1
        var moment = _moment(sums[0], 0, count)
        if moment != zeroth:
            _fail("zeroth moment drift")
        _append_side(words, cosine_values, sums, 0, count, exacts, keep_exact)
        _append_side(words, sine_values, sums, 1, count, exacts, keep_exact)
        count += 1
    return words^


def derive_endpoints(
    nodes: List[UInt64],
    weights: List[UInt64],
    cosine: List[UInt64],
    sine: List[UInt64],
) raises -> List[UInt64]:
    """Return the 2816 tight endpoints for counts 1 through 64.

    Args:
        nodes: The five stored Gauss-Legendre nodes.
        weights: The five stored Gauss-Legendre weights.
        cosine: The eleven stored cosine coefficients.
        sine: The eleven stored sine coefficients.

    Returns:
        Low then high for cosine 0 through 10, then sine 0 through 10,
        for each count from 1 through 64.

    Raises:
        Error: A list has the wrong length, the zeroth moment drifts,
        or an endpoint does not fit in binary64.
    """
    var exacts = List[String]()
    return _derive_words(nodes, weights, cosine, sine, exacts, False)


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
        text += String(digits[byte = nibble : nibble + 1])
        shift -= 4
    return text


def _parse_word(text: String) raises -> UInt64:
    """Return one `0x` word.

    Args:
        text: A hexadecimal encoding, with an optional `0x` prefix.

    Returns:
        The encoding.

    Raises:
        Error: The text is not one to sixteen hexadecimal digits.
    """
    var data = text.as_bytes()
    var index = 0
    if len(data) >= 2 and data[0] == 48 and (data[1] == 120 or data[1] == 88):
        index = 2
    if index >= len(data):
        _fail("malformed coefficient word")
    var value = UInt64(0)
    var digits = 0
    while index < len(data):
        var byte = data[index]
        var nibble = -1
        if byte >= 48 and byte <= 57:
            nibble = Int(byte) - 48
        elif byte >= 65 and byte <= 70:
            nibble = Int(byte) - 55
        elif byte >= 97 and byte <= 102:
            nibble = Int(byte) - 87
        if nibble < 0 or digits == 16:
            _fail("malformed coefficient word")
        value = (value << 4) | UInt64(nibble)
        digits += 1
        index += 1
    return value


def _word_list(doc: PyJson, key: String) raises -> List[UInt64]:
    """Return one hex list from a derivation payload.

    Args:
        doc: The payload document.
        key: `nodes`, `weights`, `cosine`, or `sine`.

    Returns:
        The encodings in order.

    Raises:
        Error: A word is malformed.
    """
    var node = doc.at(doc.root, key)
    var count = doc.length(node)
    var words = List[UInt64]()
    var index = 0
    while index < count:
        words.append(_parse_word(doc.text(doc.item(node, index))))
        index += 1
    return words^


def _side_list(
    mut doc: PyJson,
    exacts: List[String],
    words: List[UInt64],
    exact_at: Int,
    word_at: Int,
) raises -> Int:
    """Return eleven coefficient records.

    Args:
        doc: The output document.
        exacts: The exact spellings.
        words: The endpoint encodings.
        exact_at: The first exact spelling for this side.
        word_at: The first encoding for this side.

    Returns:
        The JSON list node.

    Raises:
        Error: A record cannot be stored.
    """
    var side = doc.new_list()
    var index = 0
    while index < 11:
        var item = doc.new_dict()
        doc.set(item, "exact", doc.new_str(exacts[exact_at + index]))
        var pair = doc.new_list()
        doc.append(pair, doc.new_str(_hex_word(words[word_at + 2 * index])))
        doc.append(pair, doc.new_str(_hex_word(words[word_at + 2 * index + 1])))
        doc.set(item, "words", pair)
        doc.append(side, item)
        index += 1
    return side


def coefficient_rows_json(
    nodes: List[UInt64],
    weights: List[UInt64],
    cosine: List[UInt64],
    sine: List[UInt64],
) raises -> String:
    """Return the 64 derived rows as JSON.

    Args:
        nodes: The five stored Gauss-Legendre nodes.
        weights: The five stored Gauss-Legendre weights.
        cosine: The eleven stored cosine coefficients.
        sine: The eleven stored sine coefficients.

    Returns:
        A JSON list. Each row has `count`, `cosine`, and `sine`. Each
        coefficient has `exact` and two `words`.

    Raises:
        Error: A list has the wrong length, the zeroth moment drifts,
        or an endpoint does not fit in binary64.
    """
    var exacts = List[String]()
    var words = _derive_words(nodes, weights, cosine, sine, exacts, True)
    if len(exacts) != 1408 or len(words) != 2816:
        _fail("wrong derived table shape")
    var doc = PyJson()
    var rows = doc.new_list()
    var count = 1
    while count <= 64:
        var row = doc.new_dict()
        var base = (count - 1) * 22
        doc.set(row, "count", doc.new_int(count))
        doc.set(
            row,
            "cosine",
            _side_list(doc, exacts, words, base, base * 2),
        )
        doc.set(
            row,
            "sine",
            _side_list(doc, exacts, words, base + 11, base * 2 + 22),
        )
        doc.append(rows, row)
        count += 1
    doc.root = rows
    return doc.dumps()


def _append_coefficient_side(
    mut source: PyJson, mut out: PyJson, flat: Int, side: Int
) raises:
    """Append one side's words onto `flat`.

    Args:
        source: The derived-row document.
        out: The document that owns `flat`.
        flat: The destination list.
        side: The cosine or sine list in `source`.

    Raises:
        Error: The side does not hold eleven pairs.
    """
    var coefficients = source.length(side)
    if coefficients != 11:
        _fail("wrong derived table shape")
    var index = 0
    while index < coefficients:
        var words = source.at(source.item(side, index), "words")
        if source.length(words) != 2:
            _fail("wrong derived table shape")
        out.append(flat, out.new_str(source.text(source.item(words, 0))))
        out.append(flat, out.new_str(source.text(source.item(words, 1))))
        index += 1


def coefficient_words_json(payload: String) raises -> String:
    """Return the derived coefficient words in reviewed order.

    Args:
        payload: The JSON rows from `coefficient_rows_json`. Each row has
            `cosine` and `sine`. Each coefficient has two `words`.

    Returns:
        A JSON list of 2816 `0x` words. Cosine words precede sine words
        in each row, and rows stay in count order.

    Raises:
        Error: The row list, a side, or a word pair has the wrong length.
    """
    var source = PyJson.parse(payload)
    var count = source.length(source.root)
    if count != 64:
        _fail("wrong derived table shape")
    var out = PyJson()
    var flat = out.new_list()
    var row_index = 0
    while row_index < count:
        var row = source.item(source.root, row_index)
        _append_coefficient_side(source, out, flat, source.at(row, "cosine"))
        _append_coefficient_side(source, out, flat, source.at(row, "sine"))
        row_index += 1
    if out.length(flat) != 2816:
        _fail("wrong derived table shape")
    out.root = flat
    return out.dumps()


def verified_table_integers(payload: String) raises -> String:
    """Check the derived coefficient words, then the stored table.

    Args:
        payload: JSON with `rows` and `source`. `rows` is the derived row
            list. `source` is the table text.

    Returns:
        A JSON list of unsigned decimal words read from the table.

    Raises:
        Error: The rows changed, or the table does not match them. The
            rows are checked before the table.
    """
    var doc = PyJson.parse(payload)
    var words = coefficient_words_json(
        doc.subtree(doc.at(doc.root, "rows")).dumps()
    )
    return hex_integers_json(
        verify_moment_table(doc.text(doc.at(doc.root, "source")), words)
    )


def moment_payload_from_rows(rows: String) raises -> String:
    """Derive the coefficient words, then build the moment payload.

    Args:
        rows: The JSON rows from the moment derivation.

    Returns:
        JSON with `be64`, `be64_sha256`, `byte_count`, and `source_sha256`.

    Raises:
        Error: The rows changed, or a coefficient word is malformed. The
            rows are checked before the payload is built.
    """
    return moment_payload_json(coefficient_words_json(rows))


def moment_source_from_rows(rows: String) raises -> String:
    """Derive the coefficient words, then write the table source.

    Args:
        rows: The JSON rows from the moment derivation.

    Returns:
        The generated Mojo source, including the trailing newline.

    Raises:
        Error: The rows changed, or a coefficient word is malformed. The
            rows are checked before the source is written.
    """
    return moment_source(coefficient_words_json(rows))


def moment_products_from_rows(rows: String) raises -> String:
    """Write the table source, then the moment payload.

    Args:
        rows: The JSON rows from the moment derivation.

    Returns:
        JSON with `source` and `be64`. `source` is the generated table
        text. `be64` is the payload hex.

    Raises:
        Error: The rows changed, or a coefficient word is malformed. The
            source is written before the payload.
    """
    var words = coefficient_words_json(rows)
    var source = moment_source(words)
    var payload = PyJson.parse(moment_payload_json(words))
    var doc = PyJson()
    var root = doc.new_dict()
    doc.set(root, "source", doc.new_str(source))
    doc.set(
        root,
        "be64",
        doc.new_str(payload.text(payload.at(payload.root, "be64"))),
    )
    doc.root = root
    return doc.dumps()


def write_moment_products(rows: String, output: Path) raises -> String:
    """Write the table source, then the payload bytes.

    Args:
        rows: The JSON rows from the moment derivation.
        output: The file that receives the payload bytes.

    Returns:
        The generated table source.

    Raises:
        Error: The rows changed, a coefficient word is malformed, or the
            payload hex is not bytes. The source is written before the
            bytes are read.
    """
    var doc = PyJson.parse(moment_products_from_rows(rows))
    var payload = from_hex(doc.text(doc.at(doc.root, "be64")))
    output.write_bytes(Span(payload))
    return doc.text(doc.at(doc.root, "source"))


def coefficient_integers_from_rows(rows: String) raises -> String:
    """Derive the coefficient words, then read them as integers.

    Args:
        rows: The JSON rows from the moment derivation.

    Returns:
        A JSON list of unsigned decimal words. Cosine words precede sine
        words in each row.

    Raises:
        Error: The rows changed, or a coefficient word is malformed. The
            rows are checked before the words are read.
    """
    return hex_integers_json(coefficient_words_json(rows))


def coefficient_rows_payload(payload: String) raises -> String:
    """Return the derived rows for one JSON word document.

    Args:
        payload: JSON with `nodes`, `weights`, `cosine`, and `sine`.

    Returns:
        The 64 count rows. Each coefficient has its exact value and two words.

    Raises:
        Error: A word list has the wrong length, a word is malformed,
        or an endpoint does not fit in binary64.
    """
    var doc = PyJson.parse(payload)
    return coefficient_rows_json(
        _word_list(doc, "nodes"),
        _word_list(doc, "weights"),
        _word_list(doc, "cosine"),
        _word_list(doc, "sine"),
    )


def coefficient_rows_from_decimals(payload: String) raises -> String:
    """Spell four stored word lists, then derive the moment rows.

    Args:
        payload: JSON with `nodes`, `weights`, `cosine`, and `sine`.
            Each value is a list of unsigned decimal words.

    Returns:
        The 64 count rows. Each coefficient has its exact value and two words.

    Raises:
        Error: A decimal word is malformed, or the derivation changed.
            The lists are spelled in that order before the rows are derived.
    """
    var doc = PyJson.parse(payload)
    var names = List[String]()
    names.append("nodes")
    names.append("weights")
    names.append("cosine")
    names.append("sine")
    var hexed = PyJson()
    var root = hexed.new_dict()
    var index = 0
    while index < len(names):
        var name = names[index]
        var spelled = PyJson.parse(
            hex_words_json(doc.subtree(doc.at(doc.root, name)).dumps())
        )
        var rows = hexed.new_list()
        var count = spelled.length(spelled.root)
        var cursor = 0
        while cursor < count:
            hexed.append(
                rows,
                hexed.new_str(spelled.text(spelled.item(spelled.root, cursor))),
            )
            cursor += 1
        hexed.set(root, name, rows)
        index += 1
    hexed.root = root
    return coefficient_rows_payload(hexed.dumps())
