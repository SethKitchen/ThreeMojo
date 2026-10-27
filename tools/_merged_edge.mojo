# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Put a module path on a runtime-boundary edge.

The path is written first. Keys already stored on the edge keep their
positions, and a stored path replaces the one just written.
"""

from tools._json_tools import quote_ascii
from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_LIST,
    PY_NONE,
    PY_STR,
    PyJson,
)


def _dump(doc: PyJson, node: Int) raises -> String:
    """Return JSON in stored key order, with no spaces.

    Args:
        doc: The document.
        node: The value.

    Returns:
        The text `json.dumps` writes with `separators=(',', ':')`.

    Raises:
        Error: A nested value cannot be read.
    """
    var kind = doc.kind(node)
    if kind == PY_DICT:
        var out = String("{")
        var count = doc.length(node)
        var index = 0
        while index < count:
            if index > 0:
                out += ","
            out += quote_ascii(doc.key(node, index))
            out += ":"
            out += _dump(doc, doc.value(node, index))
            index += 1
        out += "}"
        return out
    if kind == PY_LIST:
        var out = String("[")
        var count = doc.length(node)
        var index = 0
        while index < count:
            if index > 0:
                out += ","
            out += _dump(doc, doc.item(node, index))
            index += 1
        out += "]"
        return out
    if kind == PY_STR:
        return quote_ascii(doc.text(node))
    if kind == PY_BOOL:
        return "true" if doc.flag(node) else "false"
    if kind == PY_NONE:
        return "null"
    return doc.text(node)


def merged_edge(payload: String) raises -> String:
    """Return an edge with its module path written first.

    Args:
        payload: JSON with `path` and `edge`.

    Returns:
        The edge JSON. `path` is first. A path already stored on `edge`
        keeps that position and replaces the new path.

    Raises:
        Error: `path` or `edge` is missing.
    """
    var doc = PyJson.parse(payload)
    var path = doc.text(doc.at(doc.root, "path"))
    var edge = doc.at(doc.root, "edge")
    var out = doc.new_dict()
    doc.set(out, "path", doc.new_str(path))
    var count = doc.length(edge)
    var index = 0
    while index < count:
        var key = doc.key(edge, index)
        var copied = doc.copy_node(doc.value(edge, index))
        doc.set(out, key, copied)
        index += 1
    return _dump(doc, out)
