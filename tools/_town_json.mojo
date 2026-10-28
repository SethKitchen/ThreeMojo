# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""JSON readers and writers that the CARLA town and vehicle tools share.

The readers take one `PyJson` node and refuse a value of the wrong kind.
The writers keep insertion order, as Python's `json` module does.
"""

from tools._json_tools import quote_ascii
from tools._python_float import parse_float
from tools._python_json import (
    MISSING,
    PY_BOOL,
    PY_DICT,
    PY_FLOAT,
    PY_INT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)


def json_number(doc: PyJson, node: Int) raises -> Float64:
    """Return a JSON number as `float`.

    Args:
        doc: The document.
        node: The number node.

    Returns:
        The value.

    Raises:
        Error: If the node is not a number.
    """
    var kind = doc.kind(node)
    if kind == PY_FLOAT:
        return doc.number(node)
    if kind == PY_INT:
        return parse_float(doc.text(node))
    raise Error("coordinate is not a number")


def json_index(doc: PyJson, node: Int) raises -> Int:
    """Return a JSON integer index.

    Args:
        doc: The document.
        node: The integer node.

    Returns:
        The value.

    Raises:
        Error: If the node is not an integer.
    """
    if doc.kind(node) != PY_INT:
        raise Error("index is not an integer")
    return Int(parse_float(doc.text(node)))


def json_int(doc: PyJson, node: Int, message: String) raises -> Int:
    """Return a JSON integer, or raise `message`.

    Args:
        doc: The document.
        node: The integer node.
        message: The error text.

    Returns:
        The value.

    Raises:
        Error: `message`, if the node is not an integer.
    """
    if doc.kind(node) != PY_INT:
        raise Error(message)
    return Int(parse_float(doc.text(node)))


def json_named_int(doc: PyJson, node: Int, name: String) raises -> Int:
    """Return a JSON integer, or raise that `name` is not an integer.

    Args:
        doc: The document.
        node: The integer node.
        name: The name the error gives the value.

    Returns:
        The value.

    Raises:
        Error: If the node is not an integer.
    """
    if doc.kind(node) != PY_INT:
        raise Error(name + " is not an integer")
    return Int(parse_float(doc.text(node)))


def json_text(doc: PyJson, node: Int, message: String) raises -> String:
    """Return a JSON string, or raise `message`.

    Args:
        doc: The document.
        node: The string node.
        message: The error text.

    Returns:
        The text.

    Raises:
        Error: `message`, if the node is not a string.
    """
    if doc.kind(node) != PY_STR:
        raise Error(message)
    return doc.text(node)


def json_member(doc: PyJson, node: Int, key: String) raises -> Int:
    """Return a member, or raise as Python's `KeyError` does.

    Args:
        doc: The document.
        node: The object node.
        key: The member name.

    Returns:
        The member node.

    Raises:
        Error: If the member is absent.
    """
    var found = doc.get(node, key)
    if found == MISSING:
        raise Error("KeyError: '" + key + "'")
    return found


def json_vec3(
    doc: PyJson,
    node: Int,
    mut xs: List[Float64],
    mut ys: List[Float64],
    mut zs: List[Float64],
) raises:
    """Append a list of 3-vectors to three coordinate lists.

    Args:
        doc: The document.
        node: The list node.
        xs: The x coordinates, appended to.
        ys: The y coordinates, appended to.
        zs: The z coordinates, appended to.

    Raises:
        Error: If the node is not a list of three numbers each.
    """
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST or doc.length(point) != 3:
            raise Error("vector is not 3 numbers")
        xs.append(json_number(doc, doc.item(point, 0)))
        ys.append(json_number(doc, doc.item(point, 1)))
        zs.append(json_number(doc, doc.item(point, 2)))


def json_vec2(
    doc: PyJson, node: Int, mut xs: List[Float64], mut ys: List[Float64]
) raises:
    """Append a list of 2-vectors to two coordinate lists.

    Args:
        doc: The document.
        node: The list node.
        xs: The x coordinates, appended to.
        ys: The y coordinates, appended to.

    Raises:
        Error: If the node is not a list of two numbers each.
    """
    if doc.kind(node) != PY_LIST:
        raise Error("vectors are not a list")
    for index in range(doc.length(node)):
        var point = doc.item(node, index)
        if doc.kind(point) != PY_LIST or doc.length(point) != 2:
            raise Error("vector is not 2 numbers")
        xs.append(json_number(doc, doc.item(point, 0)))
        ys.append(json_number(doc, doc.item(point, 1)))


def json_triangles(doc: PyJson, node: Int, count: Int) raises -> List[Int]:
    """Return flat triangle indices, each below `count`.

    Args:
        doc: The document.
        node: The list of index triples.
        count: The number of vertices.

    Returns:
        Three indices per triangle.

    Raises:
        Error: If a triangle is not three integers in range.
    """
    if doc.kind(node) != PY_LIST:
        raise Error("triangles are not a list")
    var out = List[Int]()
    for index in range(doc.length(node)):
        var triangle = doc.item(node, index)
        if doc.kind(triangle) != PY_LIST or doc.length(triangle) != 3:
            raise Error("triangle is not three indices")
        for corner in range(3):
            var face = json_index(doc, doc.item(triangle, corner))
            if face < 0 or face >= count:
                raise Error("index out of range")
            out.append(face)
    return out^


def json_quote(text: String) -> String:
    """Return one JSON string that escapes only quotes and backslashes.

    Args:
        text: The text.

    Returns:
        The quoted text.
    """
    var out = String('"')
    var raw = text.as_bytes()
    for index in range(len(raw)):
        var byte = raw[index]
        if byte == 34 or byte == 92:
            out += "\\"
            out += chr(Int(byte))
        else:
            out += chr(Int(byte))
    out += '"'
    return out


def json_compact(doc: PyJson, node: Int) raises -> String:
    """Return JSON with no spaces, in insertion order.

    Args:
        doc: The document.
        node: The node to write.

    Returns:
        The JSON text.

    Raises:
        Error: If the document cannot be read.
    """
    var kind = doc.kind(node)
    if kind == PY_DICT:
        var out = String("{")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ","
            out += json_quote(doc.key(node, index))
            out += ":"
            out += json_compact(doc, doc.value(node, index))
        out += "}"
        return out
    if kind == PY_LIST:
        var out = String("[")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ","
            out += json_compact(doc, doc.item(node, index))
        out += "]"
        return out
    if kind == PY_STR:
        return json_quote(doc.text(node))
    if kind == PY_BOOL:
        if doc.flag(node):
            return "true"
        return "false"
    if kind == PY_NONE:
        return "null"
    return doc.text(node)


def json_dump(doc: PyJson, node: Int) raises -> String:
    """Return JSON in insertion order, as `json.dumps` writes it.

    Args:
        doc: The document.
        node: The node to write.

    Returns:
        The JSON text.

    Raises:
        Error: If the document cannot be read.
    """
    var kind = doc.kind(node)
    if kind == PY_STR:
        return quote_ascii(doc.text(node))
    if kind == PY_INT or kind == PY_FLOAT:
        return doc.text(node)
    if kind == PY_BOOL:
        return "true" if doc.flag(node) else "false"
    if kind == PY_LIST:
        var out = String("[")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ", "
            out += json_dump(doc, doc.item(node, index))
        out += "]"
        return out
    if kind == PY_DICT:
        var out = String("{")
        var count = doc.length(node)
        for index in range(count):
            if index > 0:
                out += ", "
            out += quote_ascii(doc.key(node, index))
            out += ": "
            out += json_dump(doc, doc.value(node, index))
        out += "}"
        return out
    return "null"
