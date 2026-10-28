# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the sampled-value result.

The status, the three fixed counts, and the scope sentence are fixed.
The repository root, the two measured counts, the primitive digest, the
source digests, and the typed edges are copied from the check that just ran.
"""

from tools._carla_assets import dumps_indent
from tools._framed_sha256 import framed_sha256
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
from tools._sampled_closure import sampled_closure


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


def sampled_result_from_frame(
    frame: Span[UInt8, _], meta: String
) raises -> String:
    """Hash the framed sources, then build the sampled result.

    Args:
        frame: Length lines followed by the exact payload bytes.
        meta: JSON with `root`, `shared`, `modules`, `primitive`,
            `names`, and `successors`.

    Returns:
        The result JSON in historical field order.

    Raises:
        Error: A frame is invalid, the digest count disagrees, or a
            result field changed. The digests are read before the result.
            A count error is `sampled source frame changed`.
    """
    var digests = PyJson.parse(framed_sha256(frame))
    var doc = PyJson.parse(meta)
    var names = doc.at(doc.root, "names")
    if digests.length(digests.root) != doc.length(names):
        var closure = PyJson.parse(sampled_closure())
        raise Error(closure.text(closure.at(closure.root, "frame")))
    var sources = String("{")
    var count = doc.length(names)
    var index = 0
    while index < count:
        if index > 0:
            sources += ","
        sources += quote_ascii(doc.text(doc.item(names, index)))
        sources += ":"
        sources += quote_ascii(digests.text(digests.item(digests.root, index)))
        index += 1
    sources += "}"
    var payload = String('{"root":')
    payload += quote_ascii(doc.text(doc.at(doc.root, "root")))
    payload += ',"shared":'
    payload += doc.text(doc.at(doc.root, "shared"))
    payload += ',"modules":'
    payload += doc.text(doc.at(doc.root, "modules"))
    payload += ',"primitive":'
    payload += quote_ascii(doc.text(doc.at(doc.root, "primitive")))
    payload += ',"sources":'
    payload += sources
    payload += ',"successors":'
    payload += _dump(doc, doc.at(doc.root, "successors"))
    payload += "}"
    return sampled_value_result(payload)


def indented_sampled_result_from_frame(
    frame: Span[UInt8, _], meta: String
) raises -> String:
    """Hash the framed sources, build the result, then indent it.

    Args:
        frame: Length lines followed by the exact payload bytes.
        meta: JSON with `root`, `shared`, `modules`, `primitive`,
            `names`, and `successors`.

    Returns:
        JSON with `result` and `indented`. `result` is the compact
        result. `indented` is that result with two-space indentation
        and a final newline.

    Raises:
        Error: A frame is invalid or a result field changed. The frame
            and the result are read before the result is indented.
    """
    var compact = sampled_result_from_frame(frame, meta)
    var doc = PyJson.parse(compact)
    var indented = dumps_indent(doc, doc.root, 2) + "\n"
    return '{"result":' + compact + ',"indented":' + quote_ascii(indented) + "}"
