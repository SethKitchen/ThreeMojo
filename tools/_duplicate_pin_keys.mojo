# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Refuse a repeated key in a runtime pin document.

The checker reads the bytes it is given. It does not read the repository.
A repeated key is reported without a contract prefix. Invalid JSON uses
the parser text.
"""

from tools._python_json import loads


def _skip_json_space(text: String, mut index: Int):
    """Move past ASCII space in a JSON document.

    Args:
        text: The JSON text.
        index: The current byte index.
    """
    var data = text.as_bytes()
    var count = len(data)
    while index < count:
        var byte = data[index]
        if byte != 32 and byte != 9 and byte != 10 and byte != 13:
            return
        index += 1


def _json_hex(byte: Int) raises -> Int:
    """Return one hex value.

    Args:
        byte: An ASCII hex digit.

    Returns:
        The value from 0 through 15.

    Raises:
        Error: The byte is not a hex digit.
    """
    if byte >= 48 and byte <= 57:
        return byte - 48
    if byte >= 65 and byte <= 70:
        return byte - 55
    if byte >= 97 and byte <= 102:
        return byte - 87
    raise Error("JSONDecodeError")


def _json_string(text: String, mut index: Int) raises -> String:
    """Read one JSON string and return its decoded text.

    Args:
        text: The JSON text.
        index: The index of the opening quote.

    Returns:
        The decoded string.

    Raises:
        Error: The string is not closed or an escape is invalid.
    """
    var data = text.as_bytes()
    var count = len(data)
    if index >= count or data[index] != 34:
        raise Error("JSONDecodeError")
    index += 1
    var out = String("")
    while index < count:
        var byte = data[index]
        index += 1
        if byte == 34:
            return out
        if byte != 92:
            out += chr(Int(byte))
            continue
        if index >= count:
            raise Error("JSONDecodeError")
        var escaped = data[index]
        index += 1
        if escaped == 34 or escaped == 92 or escaped == 47:
            out += chr(Int(escaped))
        elif escaped == 98:
            out += chr(8)
        elif escaped == 102:
            out += chr(12)
        elif escaped == 110:
            out += chr(10)
        elif escaped == 114:
            out += chr(13)
        elif escaped == 116:
            out += chr(9)
        elif escaped == 117:
            if index + 4 > count:
                raise Error("JSONDecodeError")
            var code = 0
            var shift = 0
            while shift < 4:
                code = code * 16 + _json_hex(Int(data[index]))
                index += 1
                shift += 1
            out += chr(code)
        else:
            raise Error("JSONDecodeError")
    raise Error("JSONDecodeError")


def _json_value(text: String, mut index: Int) raises:
    """Skip one JSON value and refuse a repeated object key.

    Args:
        text: The JSON text.
        index: The start of the value.

    Raises:
        Error: The value is not JSON, or an object key is repeated.
    """
    _skip_json_space(text, index)
    var data = text.as_bytes()
    var count = len(data)
    if index >= count:
        raise Error("JSONDecodeError")
    var byte = data[index]
    if byte == 34:
        _ = _json_string(text, index)
        return
    if byte == 123:
        _json_object(text, index)
        return
    if byte == 91:
        _json_array(text, index)
        return
    while index < count:
        var mark = data[index]
        if (
            mark == 44
            or mark == 125
            or mark == 93
            or mark == 32
            or mark == 9
            or mark == 10
            or mark == 13
        ):
            return
        index += 1


def _json_object(text: String, mut index: Int) raises:
    """Read one JSON object and refuse a repeated key.

    Args:
        text: The JSON text.
        index: The index of `{`.

    Raises:
        Error: The object is not JSON, or a key is repeated.
    """
    var data = text.as_bytes()
    var count = len(data)
    index += 1
    _skip_json_space(text, index)
    if index < count and data[index] == 125:
        index += 1
        return
    var keys = List[String]()
    while True:
        _skip_json_space(text, index)
        var key = _json_string(text, index)
        var seen = 0
        while seen < len(keys):
            if keys[seen] == key:
                raise Error("duplicate runtime source pin key: " + key)
            seen += 1
        keys.append(key)
        _skip_json_space(text, index)
        if index >= count or data[index] != 58:
            raise Error("JSONDecodeError")
        index += 1
        _json_value(text, index)
        _skip_json_space(text, index)
        if index >= count:
            raise Error("JSONDecodeError")
        if data[index] == 125:
            index += 1
            return
        if data[index] != 44:
            raise Error("JSONDecodeError")
        index += 1


def _json_array(text: String, mut index: Int) raises:
    """Read one JSON array.

    Args:
        text: The JSON text.
        index: The index of `[`.

    Raises:
        Error: The array is not JSON, or a nested object key is repeated.
    """
    var data = text.as_bytes()
    var count = len(data)
    index += 1
    _skip_json_space(text, index)
    if index < count and data[index] == 93:
        index += 1
        return
    while True:
        _json_value(text, index)
        _skip_json_space(text, index)
        if index >= count:
            raise Error("JSONDecodeError")
        if data[index] == 93:
            index += 1
            return
        if data[index] != 44:
            raise Error("JSONDecodeError")
        index += 1


def reject_duplicate_pin_keys(payload: Span[UInt8, _]) raises:
    """Refuse a repeated key before a pin is placed.

    Args:
        payload: The active pin bytes.

    Raises:
        Error: A key is repeated, or the bytes are not JSON. The repeated
            key has no contract prefix. Invalid JSON uses the parser text.
    """
    var text = String(from_utf8_lossy=payload)
    var index = 0
    try:
        _json_value(text, index)
        _skip_json_space(text, index)
        if index != len(text.as_bytes()):
            raise Error("JSONDecodeError")
    except error:
        var message = String(error)
        if message.startswith("duplicate runtime source pin key:"):
            raise error
        _ = loads(payload)
