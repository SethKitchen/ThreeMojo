# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read UModel material text.

    carla_mat_text mat FILE
    carla_mat_text props FILE

`mat` prints the `key=value` pairs of a `.mat` file. Keys that start with
`Other` are collected in `_others`. `props` prints the parent, the vector
and scalar parameters, and whether the blend is translucent or masked.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._json_tree import JsonTree
from tools._python_float import parse_float


def mat_text(path: String) raises -> String:
    """Return a `.mat` file as JSON.

    Args:
        path: The UModel `.mat` file.

    Returns:
        An object of string values, plus `_others`, an array of the
        `Other` values.

    Raises:
        Error: If the file cannot be read.
    """
    var text = _read(path)
    var tree = JsonTree()
    var obj = tree.object()
    var others = tree.array()
    var lines = _lines(text)
    for index in range(len(lines)):
        var line = lines[index]
        var eq = line.find("=")
        if eq < 0:
            continue
        var key = String(line[byte=:eq])
        var value = String(line[byte = eq + 1 :])
        if key.startswith("Other"):
            tree.append(others, tree.string(value))
        else:
            tree.set(obj, key, tree.string(value))
    tree.set(obj, "_others", others)
    return tree.dumps(obj, False)


def props_text(path: String) raises -> String:
    """Return a `.props.txt` file as JSON.

    Args:
        path: The UModel `.props.txt` file.

    Returns:
        An object with `parent`, `vectors`, `scalars`, `translucent` and
        `masked`.

    Raises:
        Error: If the file cannot be read or a number is not a float.
    """
    var text = _read(path)
    var tree = JsonTree()
    var obj = tree.object()
    tree.set(obj, "parent", tree.string(_parent(text)))
    tree.set(obj, "vectors", _vectors(tree, text))
    tree.set(obj, "scalars", _scalars(tree, text))
    tree.set(
        obj,
        "translucent",
        tree.boolean(_has(text, "BlendMode = BLEND_Translucent")),
    )
    tree.set(
        obj, "masked", tree.boolean(_has(text, "BlendMode = BLEND_Masked"))
    )
    return tree.dumps(obj, False)


def _read(path: String) raises -> String:
    """Read text as UTF-8 with replacement, and universal newlines."""
    return _decode(Path(path).read_bytes())


def _decode(data: List[UInt8]) -> String:
    """Decode UTF-8, replacing an invalid sequence with U+FFFD.

    CR, LF and CRLF become LF, as a text-mode file does. A valid sequence
    becomes one code point.
    """
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
            out += chr(0xFFFD)
            index += 1
            continue
        out += chr(_scalar(data, index, size))
        index += size
    return out


def _scalar(data: List[UInt8], index: Int, size: Int) -> Int:
    """Return the code point of a valid UTF-8 sequence."""
    var first = Int(data[index])
    if size == 1:
        return first
    var point = first & (0x7F >> size)
    for offset in range(1, size):
        point = (point << 6) | (Int(data[index + offset]) & 0x3F)
    return point


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
    if need == 0:
        return 0
    if index + need > len(data):
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


def _lines(text: String) -> List[String]:
    """Return stripped lines."""
    var out = List[String]()
    var raw = text.as_bytes()
    var start = 0
    for index in range(len(raw) + 1):
        if index == len(raw) or raw[index] == 10:
            out.append(_strip(String(text[byte=start:index])))
            start = index + 1
    return out^


def _parent(text: String) -> String:
    """Return the first `Parent = Class'path'` capture, or empty text."""
    var raw = text.as_bytes()
    var start = 0
    for index in range(len(raw) + 1):
        if index == len(raw) or raw[index] == 10:
            var line = String(text[byte=start:index])
            var found = _parent_line(line)
            if found.byte_length() > 0:
                return found
            start = index + 1
    return String("")


def _parent_line(line: String) -> String:
    """Return the parent path when `line` is a parent declaration."""
    var prefix = String("Parent = ")
    if not line.startswith(prefix):
        return String("")
    var raw = line.as_bytes()
    var index = prefix.byte_length()
    if index >= len(raw) or not _word(raw[index]):
        return String("")
    while index < len(raw) and _word(raw[index]):
        index += 1
    if index >= len(raw) or raw[index] != 39:
        return String("")
    var path = index + 1
    var end = path
    while end < len(raw) and raw[end] != 39:
        end += 1
    if end >= len(raw):
        return String("")
    return String(line[byte=path:end])


def _vectors(mut tree: JsonTree, text: String) raises -> Int:
    """Return the vector parameters in find order."""
    var obj = tree.object()
    var raw = text.as_bytes()
    var index = 0
    while index < len(raw):
        var hit = _vector_at(text, index)
        if hit.found:
            var values = tree.array()
            tree.append(values, tree.number(hit.r))
            tree.append(values, tree.number(hit.g))
            tree.append(values, tree.number(hit.b))
            tree.append(values, tree.number(hit.a))
            tree.set(obj, hit.name, values)
            index = hit.end
        else:
            index += 1
    return obj


def _scalars(mut tree: JsonTree, text: String) raises -> Int:
    """Return the scalar parameters in find order."""
    var obj = tree.object()
    var raw = text.as_bytes()
    var index = 0
    while index < len(raw):
        var hit = _scalar_at(text, index)
        if hit.found:
            tree.set(obj, hit.name, tree.number(hit.r))
            index = hit.end
        else:
            index += 1
    return obj


struct _Hit(Movable):
    """One parameter match."""

    var found: Bool
    var name: String
    var r: Float64
    var g: Float64
    var b: Float64
    var a: Float64
    var end: Int

    def __init__(
        out self,
        found: Bool,
        var name: String,
        r: Float64,
        g: Float64,
        b: Float64,
        a: Float64,
        end: Int,
    ):
        """Store one match."""
        self.found = found
        self.name = name^
        self.r = r
        self.g = g
        self.b = b
        self.a = a
        self.end = end


def _miss() -> _Hit:
    """Return a failed match."""
    return _Hit(False, String(""), 0.0, 0.0, 0.0, 0.0, 0)


def _vector_at(text: String, index: Int) raises -> _Hit:
    """Try the vector parameter pattern at `index`."""
    if not _starts_at(text, index, "Name="):
        return _miss()
    var name_at = index + 5
    var cursor = name_at
    var raw = text.as_bytes()
    while cursor < len(raw):
        if raw[cursor] == 125:
            return _miss()
        if (
            raw[cursor] == 32
            and cursor + 1 < len(raw)
            and raw[cursor + 1] == 125
        ):
            var name = _strip(String(text[byte=name_at:cursor]))
            var at = _space(raw, cursor + 2)
            if not _starts_at(text, at, "ParameterValue = { R="):
                cursor += 1
                continue
            at += 21
            var red = _number(text, at)
            if not red.found or not _starts_at(text, red.end, ", G="):
                cursor += 1
                continue
            var green = _number(text, red.end + 4)
            if not green.found or not _starts_at(text, green.end, ", B="):
                cursor += 1
                continue
            var blue = _number(text, green.end + 4)
            if not blue.found or not _starts_at(text, blue.end, ", A="):
                cursor += 1
                continue
            var alpha = _number(text, blue.end + 4)
            if (
                not alpha.found
                or alpha.end + 1 >= len(raw)
                or raw[alpha.end] != 32
                or raw[alpha.end + 1] != 125
            ):
                cursor += 1
                continue
            return _Hit(
                True,
                name,
                red.value,
                green.value,
                blue.value,
                alpha.value,
                alpha.end + 2,
            )
        cursor += 1
    return _miss()


def _scalar_at(text: String, index: Int) raises -> _Hit:
    """Try the scalar parameter pattern at `index`."""
    if not _starts_at(text, index, "Name="):
        return _miss()
    var name_at = index + 5
    var cursor = name_at
    var raw = text.as_bytes()
    while cursor < len(raw):
        if raw[cursor] == 125:
            return _miss()
        if (
            raw[cursor] == 32
            and cursor + 1 < len(raw)
            and raw[cursor + 1] == 125
        ):
            var name = _strip(String(text[byte=name_at:cursor]))
            var at = _space(raw, cursor + 2)
            if not _starts_at(text, at, "ParameterValue = "):
                cursor += 1
                continue
            at += 17
            var number = _number(text, at)
            if (
                not number.found
                or number.end >= len(raw)
                or not _space_byte(raw[number.end])
            ):
                cursor += 1
                continue
            return _Hit(True, name, number.value, 0.0, 0.0, 0.0, number.end + 1)
        cursor += 1
    return _miss()


struct _Num(Movable):
    """A parsed float, or none."""

    var found: Bool
    var value: Float64
    var end: Int

    def __init__(out self, found: Bool, value: Float64, end: Int):
        """Store one number."""
        self.found = found
        self.value = value
        self.end = end


def _number(text: String, index: Int) raises -> _Num:
    """Read the parameter number and parse it as `float`."""
    var raw = text.as_bytes()
    var end = index
    while end < len(raw) and _num_byte(raw[end]):
        end += 1
    if end == index:
        return _Num(False, 0.0, index)
    return _Num(True, parse_float(String(text[byte=index:end])), end)


def _space(raw: Span[UInt8, _], index: Int) -> Int:
    """Return the first index at or after `index` that is not whitespace."""
    var at = index
    while at < len(raw) and _space_byte(raw[at]):
        at += 1
    return at


def _has(text: String, needle: String) -> Bool:
    """Return whether `needle` occurs in `text`."""
    return text.find(needle) >= 0


def _starts_at(text: String, index: Int, prefix: String) -> Bool:
    """Return whether `prefix` occurs at `index`."""
    var raw = text.as_bytes()
    var head = prefix.as_bytes()
    if index < 0 or len(raw) - index < len(head):
        return False
    for offset in range(len(head)):
        if raw[index + offset] != head[offset]:
            return False
    return True


def _strip(text: String) -> String:
    """Strip ASCII whitespace from both ends."""
    var raw = text.as_bytes()
    var start = 0
    var end = len(raw)
    while start < end and _space_byte(raw[start]):
        start += 1
    while end > start and _space_byte(raw[end - 1]):
        end -= 1
    return String(text[byte=start:end])


def _space_byte(byte: UInt8) -> Bool:
    """Return whether a byte is ASCII whitespace."""
    return (
        byte == 32
        or byte == 9
        or byte == 10
        or byte == 13
        or byte == 11
        or byte == 12
    )


def _word(byte: UInt8) -> Bool:
    """Return whether a byte is an ASCII word character."""
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    )


def _num_byte(byte: UInt8) -> Bool:
    """Return whether a byte can appear in the parameter number class."""
    return (
        (byte >= 48 and byte <= 57) or byte == 45 or byte == 46 or byte == 101
    )


def main() raises:
    """Print one material text file named on the command line."""
    var arguments = argv()
    if len(arguments) != 3 or (
        arguments[1] != "mat" and arguments[1] != "props"
    ):
        print("usage: carla_mat_text mat|props FILE", file=stderr)
        exit(2)
    try:
        if arguments[1] == "mat":
            print(mat_text(arguments[2]))
        else:
            print(props_text(arguments[2]))
    except error:
        print("carla_mat_text:", error, file=stderr)
        exit(1)
