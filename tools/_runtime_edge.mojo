# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Extend one runtime-boundary edge from a reviewed view step.

The edge keeps its stored key order. A missing step leaves the edge
unchanged.
"""

from tools._json_tools import quote_ascii
from tools._python_json import MISSING, PY_BOOL, PY_STR, PyJson


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
    var found = doc.get(
        doc.at(doc.root, "steps"), doc.text(doc.at(doc.root, "path"))
    )
    var result = doc.new_dict()
    if found == MISSING:
        doc.set(result, "extend", doc.new_bool(False))
        return _emit(doc, result)
    var edge = doc.copy_node(doc.at(doc.root, "edge"))
    doc.set(edge, "after_sha256", doc.copy_node(doc.at(found, "after_sha256")))
    doc.set(
        edge,
        "after_token_sha256",
        doc.copy_node(doc.at(found, "after_token_sha256")),
    )
    doc.set(result, "extend", doc.new_bool(True))
    doc.set(result, "edge", edge)
    return _emit(doc, result)
