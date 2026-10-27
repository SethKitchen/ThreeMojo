# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the sampled-value result.

The status, the three fixed counts, and the scope sentence are fixed.
The repository root, the two measured counts, the primitive digest, the
source digests, and the typed edges are copied from the check that just ran.
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


def sampled_value_result(payload: String) raises -> String:
    """Return the sampled-value result.

    Args:
        payload: JSON with `root`, `shared`, `modules`, `primitive`,
            `sources`, and `successors`.

    Returns:
        The result JSON in historical field order.

    Raises:
        Error: A field is missing or has the wrong JSON type.
    """
    var doc = PyJson.parse(payload)
    var root_node = doc.at(doc.root, "root")
    if doc.kind(root_node) != PY_STR:
        raise Error("sampled repository root changed")
    var shared_node = doc.at(doc.root, "shared")
    if doc.kind(shared_node) != PY_INT:
        raise Error("sampled shared function count changed")
    var module_node = doc.at(doc.root, "modules")
    if doc.kind(module_node) != PY_INT:
        raise Error("sampled reference module count changed")
    var primitive_node = doc.at(doc.root, "primitive")
    if doc.kind(primitive_node) != PY_STR:
        raise Error("sampled primitive digest changed")
    var source_node = doc.at(doc.root, "sources")
    if doc.kind(source_node) != PY_DICT:
        raise Error("sampled source digest changed")
    var successor_node = doc.at(doc.root, "successors")
    var result = doc.new_dict()
    doc.set(result, "status", doc.new_str("PASS"))
    var root = doc.copy_node(root_node)
    doc.set(result, "repo_root", root)
    doc.set(result, "copied_functions", doc.new_int(8))
    doc.set(result, "dispatch_functions", doc.new_int(6))
    doc.set(result, "additional_source_pairs", doc.new_int(3))
    var shared = doc.copy_node(shared_node)
    doc.set(result, "shared_generic_and_bridge_functions", shared)
    var modules = doc.copy_node(module_node)
    doc.set(result, "complete_reference_modules", modules)
    var primitive = doc.copy_node(primitive_node)
    doc.set(result, "primitive_graph_sha256", primitive)
    var sources = doc.copy_node(source_node)
    doc.set(result, "source_sha256", sources)
    var successors = doc.copy_node(successor_node)
    doc.set(result, "typed_boundary_successors", successors)
    doc.set(
        result,
        "scope",
        doc.new_str(
            "Current typed/conditioned source admission; historical "
            + "sampled/ARC/LINE correspondence and SPIRAL bridge with "
            + "stored-arithmetic closure; source binding is not "
            + "mathematical/runtime qualification. Separate "
            + "eligibility/translation/support source gate, "
            + "native/codegen/budget/coverage/performance remain required"
        ),
    )
    return _dump(doc, result)
