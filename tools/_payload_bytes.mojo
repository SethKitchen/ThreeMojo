# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Decode hexadecimal text with Python's `bytes.fromhex` rules.

Whitespace may separate bytes. A pair cut by whitespace or a non-hex
digit is an error. The position in that error is Python's position.
"""


def from_hex(text: String) raises -> List[UInt8]:
    """Return bytes from hex digits, as `bytes.fromhex` reads them.

    Args:
        text: Pairs of hex digits, with whitespace allowed between pairs.

    Returns:
        The bytes.

    Raises:
        Error: For any other character, or a pair cut by whitespace.
    """
    var out = List[UInt8]()
    var bytes = text.as_bytes()
    var i = 0
    while i < len(bytes):
        var byte = bytes[i]
        if byte == 32 or (byte >= 9 and byte <= 13):
            i += 1
            continue
        if i + 1 >= len(bytes):
            raise Error(
                "non-hexadecimal number found in fromhex() arg at position "
                + String(i + 1)
            )
        var high = _nibble(bytes[i], i)
        var low = _nibble(bytes[i + 1], i + 1)
        out.append(UInt8(high * 16 + low))
        i += 2
    return out^


def _nibble(byte: UInt8, at: Int) raises -> Int:
    """Return one hex digit's value.

    Args:
        byte: One character.
        at: The index Python reports for this character.

    Returns:
        The digit, from 0 through 15.

    Raises:
        Error: `byte` is not a hexadecimal digit.
    """
    if byte >= 48 and byte <= 57:
        return Int(byte) - 48
    if byte >= 97 and byte <= 102:
        return Int(byte) - 87
    if byte >= 65 and byte <= 70:
        return Int(byte) - 55
    raise Error(
        "non-hexadecimal number found in fromhex() arg at position "
        + String(at)
    )
