# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Find watched model names as Python's `in` finds them.

Each text is a length line and then that many UTF-8 bytes. An empty name
matches every text. A longer name does not match a shorter text.
"""

from tools._optional_runtime_messages import optional_runtime_messages
from tools._python_json import PyJson
from tools._watched_model_names import watched_model_names


def _contains(text: String, needle: String) -> Bool:
    """Return whether `needle` occurs in `text`.

    Args:
        text: The source text.
        needle: The watched name.

    Returns:
        True when `needle` is a substring, including the empty name.
    """
    var data = text.as_bytes()
    var pat = needle.as_bytes()
    if len(pat) == 0:
        return True
    if len(pat) > len(data):
        return False
    var limit = len(data) - len(pat)
    var index = 0
    while index <= limit:
        var matched = True
        var offset = 0
        while offset < len(pat):
            if data[index + offset] != pat[offset]:
                matched = False
                break
            offset += 1
        if matched:
            return True
        index += 1
    return False


def _mentions(text: String, names: List[String]) -> Bool:
    """Return whether any name occurs in `text`.

    Args:
        text: The source text.
        names: The watched names.

    Returns:
        True when one name is a substring.
    """
    for name in names:
        if _contains(text, name):
            return True
    return False


def _length(data: Span[UInt8, _], mut index: Int) raises -> Int:
    """Read one decimal length line.

    Args:
        data: The framed texts.
        index: The next byte. It advances past the newline.

    Returns:
        The number of bytes in the following text.

    Raises:
        Error: The length is missing, not decimal, or past the end.
    """
    var value = 0
    var digits = 0
    while index < len(data) and data[index] != 10:
        var byte = data[index]
        if byte < 48 or byte > 57 or digits == 9:
            raise Error("invalid model text length")
        value = value * 10 + Int(byte - 48)
        digits += 1
        index += 1
    if digits == 0 or index >= len(data):
        raise Error("invalid model text length")
    index += 1
    if value > len(data) - index:
        raise Error("invalid model text length")
    return value


def model_mentions(names_json: String, framed: String) raises -> String:
    """Return which framed texts contain a watched name.

    Args:
        names_json: A JSON list of names.
        framed: Length lines followed by the exact UTF-8 bytes of each text.

    Returns:
        A JSON list of booleans, one per text.

    Raises:
        Error: A length line is invalid, or `names_json` is not a list.
    """
    var doc = PyJson.parse(names_json)
    var names = List[String]()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        names.append(doc.text(doc.item(doc.root, index)))
        index += 1
    var data = framed.as_bytes()
    var cursor = 0
    var out = PyJson()
    var rows = out.new_list()
    while cursor < len(data):
        var size = _length(data, cursor)
        var text = String(framed[byte = cursor : cursor + size])
        cursor += size
        var kept = _mentions(text, names)
        out.append(rows, out.new_bool(kept))
    out.root = rows
    return out.dumps()


def named_model_mentions(framed: String, expected: Int) raises -> String:
    """Read the watched names, then find them in the framed texts.

    Args:
        framed: Length lines followed by the exact UTF-8 bytes of each text.
        expected: The number of texts the caller framed.

    Returns:
        A JSON list of booleans, one per text.

    Raises:
        Error: A length line is invalid, or the flag count differs from
            `expected`. The watched names are read before the texts.
    """
    var names = watched_model_names()
    var flags = model_mentions(names, framed)
    var doc = PyJson.parse(flags)
    if doc.length(doc.root) != expected:
        var messages = PyJson.parse(optional_runtime_messages())
        raise Error(messages.text(messages.at(messages.root, "models")))
    return flags
