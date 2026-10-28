# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the reviewed Sum2 correspondence result.

The counts and the scope text are fixed. The ideal projection and the
environment guard are copied from the checks that just ran.
"""

from tools._json_tools import quote_ascii
from tools._moment_projection import moment_sum2_projection
from tools._sum2_checkpoints import sum2_checkpoints
from tools.carla_sum2_graphs import sum2_graphs_and_imports
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


def sum2_result(payload: String) raises -> String:
    """Return the Sum2 correspondence result.

    Args:
        payload: JSON with `projection` and `environment_guard`.

    Returns:
        The result JSON in historical field order.

    Raises:
        Error: `projection` or `environment_guard` is missing. The text is
            Python's `KeyError`.
    """
    var doc = PyJson.parse(payload)
    var result = doc.new_dict()
    doc.set(result, "status", doc.new_str("PASS"))
    doc.set(result, "recurrence_operations", doc.new_int(6))
    doc.set(result, "correction_additions", doc.new_int(1))
    doc.set(result, "scalar_axes", doc.new_int(2))
    doc.set(result, "initialization", doc.new_str("positive zero"))
    doc.set(result, "term_count", doc.new_str("5 * pieces"))
    doc.set(
        result,
        "bound",
        doc.new_str("E + (u + gamma_(n-1)^2) M"),
    )
    doc.set(
        result,
        "arithmetic_premises",
        doc.new_str(
            "nearest rounding, gradual underflow, rounded terms, no"
            " reassociation or intermediate overflow"
        ),
    )
    var projection = doc.copy_node(doc.at(doc.root, "projection"))
    doc.set(result, "ideal_projection", projection)
    var guard = doc.copy_node(doc.at(doc.root, "environment_guard"))
    doc.set(result, "environment_guard", guard)
    doc.set(result, "native_codegen_qualified", doc.new_bool(False))
    return _dump(doc, result)


def sum2_projected_result(payload: String) raises -> String:
    """Project the Sum2 spiral, then return the correspondence result.

    Args:
        payload: JSON with `legacy`, `bounds`, `begin`, `end`, `interval`,
            and `environment_guard`.

    Returns:
        The result JSON in historical field order.

    Raises:
        Error: The projection changed, or `environment_guard` is missing.
    """
    var projection = moment_sum2_projection(payload)
    var doc = PyJson.parse(payload)
    var guard = doc.subtree(doc.at(doc.root, "environment_guard")).dumps()
    return sum2_result(
        '{"projection":' + projection + ',"environment_guard":' + guard + "}"
    )


def sum2_graphs_then_result(payload: String) raises -> String:
    """Check the caller graphs, then project the Sum2 spiral.

    Args:
        payload: JSON with the graph fields and the projection fields.
            The graph fields are `texts`, `checkpoints`, and `interval`.
            The projection fields are `legacy`, `bounds`, `begin`, `end`,
            `interval`, and `environment_guard`.

    Returns:
        The result JSON in historical field order.

    Raises:
        Error: A caller graph changed, or the projection changed. A graph
            error starts with `sum2 graph: `. The graphs are checked
            before the projection.
    """
    try:
        sum2_graphs_and_imports(payload)
    except error:
        raise Error("sum2 graph: " + String(error))
    return sum2_projected_result(payload)


def sum2_checkpoints_then_result(payload: String) raises -> String:
    """Read the Sum2 checkpoints, then check the caller graphs.

    Args:
        payload: JSON with the graph fields and the projection fields,
            except `checkpoints`. The graph fields are `texts` and
            `interval`. The projection fields are `legacy`, `bounds`,
            `begin`, `end`, `interval`, and `environment_guard`.

    Returns:
        The result JSON in historical field order.

    Raises:
        Error: The checkpoints cannot be written, a caller graph changed,
            or the projection changed. The checkpoints are read before
            the graphs. A graph error starts with `sum2 graph: `.
    """
    var checkpoints = PyJson.parse(sum2_checkpoints())
    var doc = PyJson.parse(payload)
    doc.set(doc.root, "checkpoints", doc.adopt(checkpoints, checkpoints.root))
    return sum2_graphs_then_result(doc.dumps())
