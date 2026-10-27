# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the fresh heading correspondence result.

The match flags and the scope text are fixed. The consumer count comes
from the consumer map that was just checked.
"""

from tools._json_tools import quote_ascii
from tools._python_json import (
    PY_BOOL,
    PY_DICT,
    PY_INT,
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
        if doc.flag(node):
            return "true"
        return "false"
    if kind == PY_NONE:
        return "null"
    return doc.text(node)


def heading_result(payload: String) raises -> String:
    """Return the fresh heading correspondence result.

    Args:
        payload: JSON with integer `consumers`, the number of stored
            consumers.

    Returns:
        The result JSON in historical field order.

    Raises:
        Error: `consumers` is missing or is not an integer.
    """
    var doc = PyJson.parse(payload)
    var count = doc.at(doc.root, "consumers")
    if doc.kind(count) != PY_INT:
        raise Error("heading consumer count changed")
    var result = doc.new_dict()
    doc.set(result, "heading_consumers", doc.copy_node(count))
    doc.set(result, "fresh_rate_and_heading_match", doc.new_bool(True))
    doc.set(
        result,
        "ideal_u_and_original_quadrant_phase_unchanged",
        doc.new_bool(True),
    )
    doc.set(
        result,
        "scope",
        doc.new_str(
            "Exact fresh/full-Jet heading source graph after k0 expansion; "
            + "no change to ideal u, quadrant eligibility or scalar evaluator"
        ),
    )
    return _dump(doc, result)
