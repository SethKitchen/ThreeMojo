# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the optional-runtime result.

The status and the scope sentences are fixed. The new module names are
copied from the tuple that was just checked.
"""

from tools._json_tools import quote_ascii
from tools._optional_runtime_modules import optional_runtime_modules
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


def optional_runtime_result(payload: String) raises -> String:
    """Return the optional-runtime result.

    Args:
        payload: JSON with `new_modules`, a list of module names.

    Returns:
        The result JSON in historical field order.

    Raises:
        Error: `new_modules` is missing or is not a list.
    """
    var doc = PyJson.parse(payload)
    var modules = doc.at(doc.root, "new_modules")
    if doc.kind(modules) != PY_LIST:
        raise Error("optional runtime module list changed")
    var result = doc.new_dict()
    doc.set(result, "status", doc.new_str("PASS"))
    var names = doc.copy_node(modules)
    doc.set(result, "new_modules", names)
    doc.set(
        result,
        "checked_error_edge",
        doc.new_str("guarded raw -> grouped origin -> checked Sum2 leaf"),
    )
    doc.set(
        result,
        "containing_model_consumers",
        doc.new_str("absent from production; standalone helper retained"),
    )
    doc.set(
        result,
        "fresh_cell_producer",
        doc.new_str(
            "original debit immediately precedes current-cell producer"
        ),
    )
    doc.set(
        result,
        "qualification",
        doc.new_str("source preconditions and dependency integrity only"),
    )
    doc.set(result, "native_execution_qualified", doc.new_bool(False))
    return _dump(doc, result)


def optional_runtime_result_from_modules() raises -> String:
    """Read the module names, then build the optional-runtime result.

    Returns:
        The result JSON. The module names are the reviewed list.

    Raises:
        Error: The module list cannot be read, or it is not a list.
    """
    var modules = optional_runtime_modules()
    return optional_runtime_result('{"new_modules":' + modules + "}")
