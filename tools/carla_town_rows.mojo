# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read one town layout file.

    carla_town_rows FILE

`FILE` is JSONL: one JSON value per line. The program prints a JSON
array of those values, in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import PyJson
from tools._town_json import json_dump


def rows_text(path: String) raises -> String:
    """Return the JSON values in a layout file.

    Args:
        path: A JSONL file. Each line is one JSON value. CR, LF and CRLF
            end a line, as a text-mode file does.

    Returns:
        A JSON array of the values, in order. An empty file is `[]`.

    Raises:
        Error: If the file cannot be read, a byte is not UTF-8, or a line
            is not JSON.
    """
    var text = _decode(Path(path).read_bytes())
    var lines = _lines(text)
    var doc = PyJson()
    var array = doc.new_list()
    for index in range(len(lines)):
        var line = lines[index]
        if line.byte_length() == 0:
            raise Error("layout line is not JSON")
        var parsed = PyJson.parse(line)
        doc.append(array, doc.adopt(parsed, parsed.root))
    return json_dump(doc, array)


def _decode(data: List[UInt8]) raises -> String:
    """Decode UTF-8 and turn CR, LF and CRLF into LF."""
    var out = String()
    var index = 0
    while index < len(data):
        var byte = Int(data[index])
        if byte == 13:
            out += "\n"
            index += 1
            if index < len(data) and data[index] == 10:
                index += 1
            continue
        if byte == 10:
            out += "\n"
            index += 1
            continue
        var size = _utf8_size(data, index)
        if size == 0:
            raise Error("layout is not UTF-8")
        out += chr(_scalar(data, index, size))
        index += size
    return out


def _utf8_size(data: List[UInt8], index: Int) -> Int:
    """Return the length of a valid UTF-8 sequence, or 0."""
    var first = Int(data[index])
    if first < 0x80:
        return 1
    var need = 0
    var min_value = 0
    if first >= 0xC2 and first <= 0xDF:
        need = 2
        min_value = 0x80
    elif first >= 0xE0 and first <= 0xEF:
        need = 3
        min_value = 0x800
    elif first >= 0xF0 and first <= 0xF4:
        need = 4
        min_value = 0x10000
    if need == 0 or index + need > len(data):
        return 0
    var point = first & (0x7F >> need)
    for offset in range(1, need):
        var next = Int(data[index + offset])
        if next < 0x80 or next > 0xBF:
            return 0
        point = (point << 6) | (next & 0x3F)
    if point < min_value or point > 0x10FFFF:
        return 0
    if point >= 0xD800 and point <= 0xDFFF:
        return 0
    if first == 0xE0 and Int(data[index + 1]) < 0xA0:
        return 0
    if first == 0xED and Int(data[index + 1]) >= 0xA0:
        return 0
    if first == 0xF0 and Int(data[index + 1]) < 0x90:
        return 0
    if first == 0xF4 and Int(data[index + 1]) >= 0x90:
        return 0
    return need


def _scalar(data: List[UInt8], index: Int, size: Int) -> Int:
    """Return the code point of a valid UTF-8 sequence."""
    var first = Int(data[index])
    if size == 1:
        return first
    var point = first & (0x7F >> size)
    for offset in range(1, size):
        point = (point << 6) | (Int(data[index + offset]) & 0x3F)
    return point


def _lines(text: String) -> List[String]:
    """Return lines without their newline, as a text file yields them."""
    var out = List[String]()
    var raw = text.as_bytes()
    var start = 0
    for index in range(len(raw)):
        if raw[index] == 10:
            out.append(String(text[byte=start:index]))
            start = index + 1
    if start < len(raw):
        out.append(String(text[byte=start:]))
    return out^


def main() raises:
    """Print the JSON values in the layout file on the command line."""
    var arguments = argv()
    if len(arguments) != 2:
        print("usage: carla_town_rows FILE", file=stderr)
        exit(2)
    try:
        print(rows_text(arguments[1]))
    except error:
        print("carla_town_rows:", error, file=stderr)
        exit(1)
