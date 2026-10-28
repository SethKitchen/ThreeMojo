# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the runtime-support result.

The status and the scope text are fixed. The repository root and the
check records are copied from the checks that just ran.
"""

from tools._carla_assets import dumps_indent
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
        if doc.flag(node):
            return "true"
        return "false"
    if kind == PY_NONE:
        return "null"
    return doc.text(node)


def runtime_support_result(payload: String) raises -> String:
    """Return the runtime-support result.

    Args:
        payload: JSON with `root`, `groups`, `successors`, `heading`,
            `optional`, and `sum2`.

    Returns:
        The result JSON in historical field order.

    Raises:
        Error: A required field is missing. The text is Python's `KeyError`.
    """
    var doc = PyJson.parse(payload)
    var result = doc.new_dict()
    doc.set(result, "status", doc.new_str("PASS"))
    doc.set(
        result,
        "scope",
        doc.new_str(
            "Current source-integrity and explicit typed/conditioned"
            " successors; "
            + "old source comparisons retain historical provenance only. "
            + "Native execution, performance and coverage are separate"
            " requirements"
        ),
    )
    var root = doc.copy_node(doc.at(doc.root, "root"))
    doc.set(result, "repo_root", root)
    var groups = doc.copy_node(doc.at(doc.root, "groups"))
    doc.set(result, "groups", groups)
    var successors = doc.copy_node(doc.at(doc.root, "successors"))
    doc.set(result, "typed_boundary_successors", successors)
    var heading = doc.copy_node(doc.at(doc.root, "heading"))
    doc.set(result, "heading_correspondence", heading)
    var optional = doc.copy_node(doc.at(doc.root, "optional"))
    doc.set(result, "optional_runtime", optional)
    var sum2 = doc.copy_node(doc.at(doc.root, "sum2"))
    doc.set(result, "sum2_correspondence", sum2)
    return _dump(doc, result)


def indented_runtime_support_result(payload: String) raises -> String:
    """Build the runtime-support result, then indent it.

    Args:
        payload: JSON with `root`, `groups`, `successors`, `heading`,
            `optional`, and `sum2`.

    Returns:
        JSON with `result` and `indented`. `result` is the compact
        result. `indented` is that result with two-space indentation
        and a final newline.

    Raises:
        Error: A required field is missing. The result is built before
            it is indented.
    """
    var compact = runtime_support_result(payload)
    var doc = PyJson.parse(compact)
    var indented = dumps_indent(doc, doc.root, 2) + "\n"
    return '{"result":' + compact + ',"indented":' + quote_ascii(indented) + "}"
