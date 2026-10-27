# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Extend one runtime-boundary edge from a reviewed view step.

The edge keeps its stored key order. A missing step leaves the edge
unchanged.
"""

from tools._json_tools import quote_ascii
from tools._python_json import MISSING, PY_BOOL, PY_LIST, PY_STR, PyJson


def _emit(doc: PyJson, node: Int) raises -> String:
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
    if kind == PY_BOOL:
        return "true" if doc.flag(node) else "false"
    if kind == PY_STR:
        return quote_ascii(doc.text(node))
    if kind == PY_LIST:
        var listed = String("[")
        var listed_count = doc.length(node)
        var listed_index = 0
        while listed_index < listed_count:
            if listed_index > 0:
                listed += ","
            listed += _emit(doc, doc.item(node, listed_index))
            listed_index += 1
        listed += "]"
        return listed
    var out = String("{")
    var count = doc.length(node)
    var index = 0
    while index < count:
        if index > 0:
            out += ","
        out += quote_ascii(doc.key(node, index))
        out += ":"
        out += _emit(doc, doc.value(node, index))
        index += 1
    out += "}"
    return out


def _extend_one(
    mut doc: PyJson, path: String, edge: Int, steps: Int
) raises -> Int:
    """Return one edge decision.

    Args:
        doc: The document that owns `edge` and `steps`.
        path: The module path.
        edge: The stored edge object.
        steps: The reviewed view steps.

    Returns:
        A decision object. `extend` is false when `path` has no step.

    Raises:
        Error: The step is missing a required digest.
    """
    var found = doc.get(steps, path)
    var result = doc.new_dict()
    if found == MISSING:
        doc.set(result, "extend", doc.new_bool(False))
        return result
    var copied = doc.copy_node(edge)
    doc.set(
        copied, "after_sha256", doc.copy_node(doc.at(found, "after_sha256"))
    )
    doc.set(
        copied,
        "after_token_sha256",
        doc.copy_node(doc.at(found, "after_token_sha256")),
    )
    doc.set(result, "extend", doc.new_bool(True))
    doc.set(result, "edge", copied)
    return result


def extend_runtime_edge(payload: String) raises -> String:
    """Return the edge after a reviewed view step, when one exists.

    Args:
        payload: JSON with `path`, `edge`, and `steps`.

    Returns:
        JSON with `extend` and, when `extend` is true, the updated `edge`.
        `after_sha256` and `after_token_sha256` come from the step.

    Raises:
        Error: The step is missing a required digest.
    """
    var doc = PyJson.parse(payload)
    var path = doc.text(doc.at(doc.root, "path"))
    var edge = doc.at(doc.root, "edge")
    var steps = doc.at(doc.root, "steps")
    var decision = _extend_one(doc, path, edge, steps)
    return _emit(doc, decision)


def extend_runtime_edges(payload: String) raises -> String:
    """Return the edge decision for each path.

    Args:
        payload: JSON with `steps` and `items`. Each item has `path` and
            `edge`.

    Returns:
        A JSON list of decisions, in item order.

    Raises:
        Error: A step is missing a required digest.
    """
    var doc = PyJson.parse(payload)
    var steps = doc.at(doc.root, "steps")
    var items = doc.at(doc.root, "items")
    var rows = doc.new_list()
    var count = doc.length(items)
    var index = 0
    while index < count:
        var item = doc.item(items, index)
        var path = doc.text(doc.at(item, "path"))
        var edge = doc.at(item, "edge")
        doc.append(rows, _extend_one(doc, path, edge, steps))
        index += 1
    return _emit(doc, rows)
