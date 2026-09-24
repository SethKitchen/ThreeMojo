# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""JavaScript's `parseFloat` and `parseInt`, for the loaders that read
text the way three.js reads it.

Both read the longest number at the start of a text, after white space,
and ignore what follows it. So `parseFloat("12px")` is 12, and
`parseInt("1.5")` is 1. Where JavaScript gives `NaN`, so do these.

**Where this differs.** White space is ASCII white space here;
JavaScript also skips the Unicode spaces. A number with more digits than
Mojo's parser reads gives NaN; JavaScript rounds it.
"""

from std.math import inf, nan


def _is_space(byte: UInt8) -> Bool:
    """Return True for an ASCII white space byte."""
    return byte == 32 or (byte >= 9 and byte <= 13)


def _is_digit(byte: UInt8) -> Bool:
    """Return True for `0` to `9`."""
    return byte >= 48 and byte <= 57


def _space_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a white space byte at `i`."""
    return i < len(bytes) and _is_space(bytes[i])


def _digit_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a digit at `i`."""
    return i < len(bytes) and _is_digit(bytes[i])


def _sign_at(bytes: Span[UInt8, _], i: Int) -> Bool:
    """Return True if there is a `+` or a `-` at `i`."""
    return i < len(bytes) and (bytes[i] == 43 or bytes[i] == 45)


def js_parse_float(text: String) -> Float64:
    """Return JavaScript's `parseFloat(text)`.

    Args:
        text: The text.

    Returns:
        The longest decimal number at the start, after white space,
        `Infinity` included; NaN when there is none.
    """
    var b = text.as_bytes()
    var n = len(b)
    var i = 0
    while _space_at(b, i):
        i += 1
    var start = i
    if _sign_at(b, i):
        i += 1
    if String(text[byte=i:]).startswith("Infinity"):
        return -inf[DType.float64]() if b[start] == 45 else inf[DType.float64]()
    var digits = 0
    while _digit_at(b, i):
        i += 1
        digits += 1
    var point = i < n and b[i] == 46
    if point:
        i += 1
        while _digit_at(b, i):
            i += 1
            digits += 1
    if digits == 0:
        return nan[DType.float64]()
    var end = i
    var exp = i < n and (b[i] == 101 or b[i] == 69)
    if exp:
        i += 1
        if _sign_at(b, i):
            i += 1
        var exponent = 0
        while _digit_at(b, i):
            i += 1
            exponent += 1
        if exponent > 0:
            end = i
    try:
        return Float64(String(text[byte=start:end]))
    except:
        return nan[DType.float64]()


def js_parse_int(text: String) -> Float64:
    """Return JavaScript's `parseInt(text)`, in base ten.

    Args:
        text: The text.

    Returns:
        The whole number at the start, after white space and a sign; NaN
        when there is none. It is a `Float64`, as a JavaScript number is,
        so that NaN can be returned.
    """
    var b = text.as_bytes()
    var i = 0
    while _space_at(b, i):
        i += 1
    var start = i
    if _sign_at(b, i):
        i += 1
    var first = i
    while _digit_at(b, i):
        i += 1
    if i == first:
        return nan[DType.float64]()
    try:
        return Float64(String(text[byte=start:i]))
    except:
        return nan[DType.float64]()
