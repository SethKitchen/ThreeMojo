# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Hash length-framed byte strings with SHA-256.

Each frame is a decimal length, a newline, and that many bytes. The digest
matches `hashlib.sha256(payload).hexdigest()`.
"""

from tools._sha256 import sha256_hex


def _length(data: Span[UInt8, _], mut index: Int) raises -> Int:
    """Read one decimal length line.

    Args:
        data: The framed bytes.
        index: The next byte. It advances past the newline.

    Returns:
        The number of payload bytes that follow.

    Raises:
        Error: The length is missing, not decimal, or past the end.
    """
    var value = 0
    var digits = 0
    while index < len(data) and data[index] != 10:
        var byte = data[index]
        if byte < 48 or byte > 57 or digits == 9:
            raise Error("invalid source frame length")
        value = value * 10 + Int(byte - 48)
        digits += 1
        index += 1
    if digits == 0 or index >= len(data):
        raise Error("invalid source frame length")
    index += 1
    if value > len(data) - index:
        raise Error("invalid source frame length")
    return value


def framed_sha256(data: Span[UInt8, _]) raises -> String:
    """Return one SHA-256 hex digest per framed payload.

    Args:
        data: Length lines followed by the exact payload bytes.

    Returns:
        A JSON list of 64 lowercase hex digits, in frame order.

    Raises:
        Error: A length line is invalid.
    """
    var out = String("[")
    var cursor = 0
    var count = 0
    while cursor < len(data):
        var size = _length(data, cursor)
        if count > 0:
            out += ","
        out += '"'
        out += sha256_hex(data[cursor : cursor + size])
        out += '"'
        cursor += size
        count += 1
    out += "]"
    return out
