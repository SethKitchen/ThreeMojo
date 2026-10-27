# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""POSIX path parts with Python's `pathlib` and `str.split` rules.

A component name is confined when `(directory / name).parent == directory`.
A basename is the text after the last `/`, as `str.split('/')` gives it.
"""

from tools._python_json import PyJson


def _push_part(mut parts: List[String], token: String):
    """Append one POSIX part, dropping empty parts and `.`.

    Args:
        parts: The parts collected so far.
        token: The text between slashes.
    """
    if token.byte_length() == 0 or token == ".":
        return
    parts.append(token)


def _parse_posix(text: String) -> List[String]:
    """Return the POSIX parts of `text`.

    Args:
        text: A path. `/` and `//` are absolute anchors.

    Returns:
        The anchor, when present, and the kept parts. `.` is dropped.
    """
    var data = text.as_bytes()
    var parts = List[String]()
    var count = len(data)
    var index = 0
    if count > 0 and data[0] == 47:
        if count > 1 and data[1] == 47 and (count == 2 or data[2] != 47):
            parts.append("//")
            index = 2
        else:
            parts.append("/")
            index = 1
            while index < count and data[index] == 47:
                index += 1
    var token = String("")
    while index < count:
        var byte = data[index]
        if byte == 47:
            _push_part(parts, token)
            token = String("")
        else:
            token += chr(Int(byte))
        index += 1
    _push_part(parts, token)
    return parts^


def _is_absolute(parts: List[String]) -> Bool:
    """Return whether `parts` begins with `/` or `//`.

    Args:
        parts: Parsed POSIX parts.

    Returns:
        True for an absolute path.
    """
    if len(parts) == 0:
        return False
    var head = parts[0]
    return head == "/" or head == "//"


def _copy(parts: List[String]) -> List[String]:
    """Return a copy of `parts`.

    Args:
        parts: Parsed POSIX parts.

    Returns:
        The same parts, in order.
    """
    var out = List[String]()
    for part in parts:
        out.append(part)
    return out^


def _parent(parts: List[String]) -> List[String]:
    """Return the parent parts, as `PurePosixPath.parent` does.

    Args:
        parts: Parsed POSIX parts.

    Returns:
        Every part but the last. A root's parent is itself.
    """
    var count = len(parts)
    if count == 0 or (count == 1 and (parts[0] == "/" or parts[0] == "//")):
        return _copy(parts)
    var out = List[String]()
    var index = 0
    while index < count - 1:
        out.append(parts[index])
        index += 1
    return out^


def _same(left: List[String], right: List[String]) -> Bool:
    """Return whether two part lists are equal.

    Args:
        left: The first parts.
        right: The second parts.

    Returns:
        True when the lengths and every part match.
    """
    if len(left) != len(right):
        return False
    var index = 0
    while index < len(left):
        if left[index] != right[index]:
            return False
        index += 1
    return True


def _join(directory: String, name: String) -> List[String]:
    """Return `directory / name` as POSIX parts.

    Args:
        directory: The base path.
        name: The added path. An absolute name replaces the base.

    Returns:
        The joined parts.
    """
    var extra = _parse_posix(name)
    if _is_absolute(extra):
        return extra^
    var out = _parse_posix(directory)
    for part in extra:
        out.append(part)
    return out^


def component_confined(directory: String, name: String) -> Bool:
    """Return whether `name` stays directly inside `directory`.

    Args:
        directory: The component directory.
        name: The component file name.

    Returns:
        True when `(directory / name).parent == directory`.
    """
    var joined = _join(directory, name)
    var parent = _parent(joined)
    var base = _parse_posix(directory)
    return _same(parent, base)


def path_basename(text: String) -> String:
    """Return the text after the last `/`.

    Args:
        text: A path. A backslash is not a separator.

    Returns:
        The last part. It is empty when `text` ends with `/`.
    """
    var data = text.as_bytes()
    var start = 0
    var index = 0
    while index < len(data):
        if data[index] == 47:
            start = index + 1
        index += 1
    return String(text[byte = start : text.byte_length()])


def require_component_names(payload: String) raises:
    """Require every component name to stay inside its directory.

    Args:
        payload: JSON with `directory` and `names`.

    Raises:
        Error: A name escapes the directory. The text is `coverage
            invariant successor: component record changed: ` and the name.
    """
    var doc = PyJson.parse(payload)
    var directory = doc.text(doc.at(doc.root, "directory"))
    var names = doc.at(doc.root, "names")
    var count = doc.length(names)
    var index = 0
    while index < count:
        var name = doc.text(doc.item(names, index))
        if not component_confined(directory, name):
            raise Error(
                "coverage invariant successor: component record changed: "
                + name
            )
        index += 1
