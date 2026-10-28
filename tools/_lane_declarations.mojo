# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every lane-control declaration in one check.

The caller supplies each source and function name. This check returns
the declaration texts in that order.
"""

from tests._python_tokens import (
    declaration_text,
    replace_firsts,
    significant_graph_pairs,
    significant_json,
    token_sha256,
)
from tools._lane_control_labels import lane_control_labels
from tools._premise_fallback import premise_fallbacks
from tools._python_json import MISSING, PY_LIST, PyJson


def lane_declarations(payload: String) raises -> String:
    """Return one declaration for each requested function.

    Args:
        payload: A JSON list. Each item has `source`, `name`, and
            `owner`. `owner` is the enclosing struct names, from the
            outside inward.

    Returns:
        A JSON list of declaration texts, in the same order.

    Raises:
        Error: A function is missing, repeated, or owned by another scope.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var rows = out.new_list()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var owners = List[String]()
        var owner = doc.at(item, "owner")
        var owner_count = doc.length(owner)
        var cursor = 0
        while cursor < owner_count:
            owners.append(doc.text(doc.item(owner, cursor)))
            cursor += 1
        out.append(
            rows,
            out.new_str(
                declaration_text(
                    doc.text(doc.at(item, "source")),
                    doc.text(doc.at(item, "name")),
                    owners,
                )
            ),
        )
        index += 1
    out.root = rows
    return out.dumps()


def declaration_match_flags(payload: String) raises -> String:
    """Read each declaration, then compare its significant tokens.

    Args:
        payload: A JSON list. Each item has `source`, `name`, `owner`, and `expected`.

    Returns:
        A JSON list of `true` or `false`, in the same order.

    Raises:
        Error: A function cannot be read, or a source cannot be tokenized.
    """
    var declared = PyJson.parse(lane_declarations(payload))
    var doc = PyJson.parse(payload)
    var count = declared.length(declared.root)
    var actuals = List[String]()
    var sources = List[String]()
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        actuals.append(
            significant_json(declared.text(declared.item(declared.root, index)))
        )
        sources.append(significant_json(doc.text(doc.at(item, "expected"))))
        index += 1
    var out = PyJson()
    var rows = out.new_list()
    index = 0
    while index < count:
        var flag = String("false")
        if actuals[index] == sources[index]:
            flag = "true"
        out.append(rows, out.new_str(flag))
        index += 1
    out.root = rows
    return out.dumps()


def declaration_texts_and_flags(payload: String) raises -> String:
    """Read every declaration, then compare the ones that have `expected`.

    Args:
        payload: A JSON list. Each item has `source`, `name`, and `owner`.
            `expected` is optional.

    Returns:
        JSON with `declared` and `flags`. `flags` follows the items that
        include `expected`.

    Raises:
        Error: A function cannot be read, or a source cannot be tokenized.
    """
    var declared_json = lane_declarations(payload)
    var declared = PyJson.parse(declared_json)
    var doc = PyJson.parse(payload)
    var count = declared.length(declared.root)
    var actuals = List[String]()
    var sources = List[String]()
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var expected = doc.get(item, "expected")
        if expected != MISSING:
            actuals.append(
                significant_json(
                    declared.text(declared.item(declared.root, index))
                )
            )
            sources.append(significant_json(doc.text(expected)))
        index += 1
    var out = PyJson()
    var flags = out.new_list()
    index = 0
    while index < len(actuals):
        var flag = String("false")
        if actuals[index] == sources[index]:
            flag = "true"
        out.append(flags, out.new_str(flag))
        index += 1
    out.root = flags
    return '{"declared":' + declared_json + ',"flags":' + out.dumps() + "}"


def checked_declaration_graphs(
    payload: String, prefix: String, invalid: String
) raises -> String:
    """Read every declaration, then check every graph when each selected one matches.

    Args:
        payload: A JSON list. Each item has `source`, `name`, `owner`, `graph`,
            and `label`. `expected` is optional.
        prefix: The contract prefix, including its trailing space.
        invalid: The failure text used when the graph list cannot be read.

    Returns:
        `restore` is false when every graph matches. It is true, with
        `declared` and `flags`, when a selected declaration differs.

    Raises:
        Error: A function cannot be read, or a graph changed while every selected declaration matches.
    """
    var body = declaration_texts_and_flags(payload)
    var parsed = PyJson.parse(body)
    var flags = parsed.at(parsed.root, "flags")
    var count = parsed.length(flags)
    var index = 0
    var restore = False
    while index < count:
        if parsed.text(parsed.item(flags, index)) != "true":
            restore = True
        index += 1
    if restore:
        return '{"restore":true,' + String(body[byte=1:])
    var declared = parsed.at(parsed.root, "declared")
    var doc = PyJson.parse(payload)
    var graphs = PyJson()
    var rows = graphs.new_list()
    count = doc.length(doc.root)
    index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var row = graphs.new_dict()
        graphs.set(
            row, "label", graphs.new_str(doc.text(doc.at(item, "label")))
        )
        graphs.set(
            row,
            "actual",
            graphs.new_str(parsed.text(parsed.item(declared, index))),
        )
        graphs.set(
            row, "source", graphs.new_str(doc.text(doc.at(item, "graph")))
        )
        graphs.append(rows, row)
        index += 1
    graphs.root = rows
    significant_graph_pairs(graphs.dumps(), prefix, invalid)
    return '{"restore":false}'


def declaration_token_checks(payload: String, prefix: String) raises:
    """Read each declaration, then require its token digest.

    Args:
        payload: A JSON list. Each item has `source`, `name`, `owner`, `token`, and `label`.
        prefix: The contract prefix, including its trailing space.

    Raises:
        Error: A function cannot be read, or a token digest changed.
    """
    var declared = PyJson.parse(lane_declarations(payload))
    var doc = PyJson.parse(payload)
    var count = declared.length(declared.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var digest = token_sha256(
            declared.text(declared.item(declared.root, index))
        )
        if digest != doc.text(doc.at(item, "token")):
            raise Error(prefix + doc.text(doc.at(item, "label")))
        index += 1


def declaration_fallbacks(payload: String) raises -> String:
    """Compare each declaration, then choose its premise fallback.

    Args:
        payload: A JSON list. Each item has `source`, `name`, `owner`,
            `expected`, and `path`.

    Returns:
        JSON with `flags` and `fallbacks`, in the same order.

    Raises:
        Error: A function cannot be read, a source cannot be tokenized, or a required field is missing.
    """
    var flags_text = declaration_match_flags(payload)
    var flags = PyJson.parse(flags_text)
    var doc = PyJson.parse(payload)
    var request = PyJson()
    var rows = request.new_list()
    var count = flags.length(flags.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var row = request.new_dict()
        var matched = flags.text(flags.item(flags.root, index)) == "true"
        request.set(row, "matched", request.new_bool(matched))
        request.set(
            row, "path", request.new_str(doc.text(doc.at(item, "path")))
        )
        request.set(
            row, "name", request.new_str(doc.text(doc.at(item, "name")))
        )
        var owners = request.new_list()
        var owner = doc.at(item, "owner")
        var owner_count = doc.length(owner)
        var slot = 0
        while slot < owner_count:
            request.append(
                owners, request.new_str(doc.text(doc.item(owner, slot)))
            )
            slot += 1
        request.set(row, "owner", owners)
        request.append(rows, row)
        index += 1
    request.root = rows
    var choices = premise_fallbacks(request.dumps())
    return '{"flags":' + flags_text + ',"fallbacks":' + choices + "}"


def restored_declaration_graphs(
    payload: String, prefix: String, invalid: String
) raises:
    """Read each restored declaration, then compare every source graph.

    Args:
        payload: JSON with `restores` and `graphs`. Each restore has
            `index`, `source`, `name`, and `owner`. Each graph has
            `label`, `actual`, and `source`.
        prefix: The contract prefix, including its trailing space.
        invalid: The failure text used when `graphs` is not a list.

    Raises:
        Error: A function cannot be read, a source cannot be tokenized, or a token list changed.
    """
    var doc = PyJson.parse(payload)
    var restores = doc.at(doc.root, "restores")
    var graph_text = doc.subtree(doc.at(doc.root, "graphs")).dumps()
    var restore_count = doc.length(restores)
    if restore_count > 0:
        var request = PyJson()
        var rows = request.new_list()
        var cursor = 0
        while cursor < restore_count:
            var item = doc.item(restores, cursor)
            var row = request.new_dict()
            request.set(
                row,
                "source",
                request.new_str(doc.text(doc.at(item, "source"))),
            )
            request.set(
                row, "name", request.new_str(doc.text(doc.at(item, "name")))
            )
            var owners = request.new_list()
            var owner = doc.at(item, "owner")
            var owner_count = doc.length(owner)
            var slot = 0
            while slot < owner_count:
                request.append(
                    owners, request.new_str(doc.text(doc.item(owner, slot)))
                )
                slot += 1
            request.set(row, "owner", owners)
            request.append(rows, row)
            cursor += 1
        request.root = rows
        var declared = PyJson.parse(lane_declarations(request.dumps()))
        var graphs = PyJson.parse(graph_text)
        if graphs.kind(graphs.root) == PY_LIST:
            cursor = 0
            while cursor < restore_count:
                var item = doc.item(restores, cursor)
                var at = Int(doc.text(doc.at(item, "index")))
                var graph = graphs.item(graphs.root, at)
                var text = declared.text(declared.item(declared.root, cursor))
                graphs.set(graph, "actual", graphs.new_str(text))
                cursor += 1
            graph_text = graphs.dumps()
    significant_graph_pairs(graph_text, prefix, invalid)


def lane_control_prepare(payload: String) raises -> String:
    """Rename the frozen texts, then read every requested declaration.

    Args:
        payload: JSON with `replacements` and `declarations`. Each
            replacement has `source`, `old`, and `new`. Each declaration
            has `source`, `name`, and `owner`.

    Returns:
        JSON with `replaced` and `declared`, in the requested order.

    Raises:
        Error: A replacement is missing a field, or a function cannot be read.
    """
    var doc = PyJson.parse(payload)
    var replaced = replace_firsts(
        doc.subtree(doc.at(doc.root, "replacements")).dumps()
    )
    var declared = lane_declarations(
        doc.subtree(doc.at(doc.root, "declarations")).dumps()
    )
    return '{"replaced":' + replaced + ',"declared":' + declared + "}"


def _request(
    mut doc: PyJson, requests: Int, source: String, name: String
) raises:
    """Append one declaration request with an empty owner.

    Args:
        doc: The document that owns the list.
        requests: The request list.
        source: The module text.
        name: The function name.

    Raises:
        Error: The request cannot be stored.
    """
    var row = doc.new_dict()
    doc.set(row, "source", doc.new_str(source))
    doc.set(row, "name", doc.new_str(name))
    doc.set(row, "owner", doc.new_list())
    doc.append(requests, row)


def lane_control_prepare_with_labels(payload: String) raises -> String:
    """Read the lane-control labels, then prepare the declarations.

    Args:
        payload: JSON with `before_source`, `current`, `declarations`, and
            `premises`. Each declaration has `name`, `before`, and `test`.
            Each premise has `name` and `source`.

    Returns:
        JSON with `replaced`, `declared`, and `labels`. The labels are the
        reviewed label object.

    Raises:
        Error: A label or a field is missing, or a function cannot be read.
            The labels are read before the declarations.
    """
    var labels_text = lane_control_labels()
    var labels = PyJson.parse(labels_text)
    var definition = labels.text(labels.at(labels.root, "definition"))
    var call = labels.text(labels.at(labels.root, "call"))
    var reference = labels.text(labels.at(labels.root, "reference"))
    var doc = PyJson.parse(payload)
    var before_source = doc.text(doc.at(doc.root, "before_source"))
    var current = doc.text(doc.at(doc.root, "current"))
    var declarations = doc.at(doc.root, "declarations")
    var premises = doc.at(doc.root, "premises")
    var out = PyJson()
    var replacements = out.new_list()
    var requests = out.new_list()
    var count = doc.length(declarations)
    var index = 0
    while index < count:
        var item = doc.item(declarations, index)
        var name = doc.text(doc.at(item, "name"))
        var before = doc.text(doc.at(item, "before"))
        var test = doc.text(doc.at(item, "test"))
        var replacement = out.new_dict()
        out.set(replacement, "source", out.new_str(before))
        out.set(replacement, "old", out.new_str(definition + name + call))
        out.set(
            replacement,
            "new",
            out.new_str(definition + reference + name + call),
        )
        out.append(replacements, replacement)
        _request(out, requests, before_source, name)
        _request(out, requests, current, name)
        _request(out, requests, test, reference + name)
        index += 1
    var premise_count = doc.length(premises)
    index = 0
    while index < premise_count:
        var item = doc.item(premises, index)
        _request(
            out,
            requests,
            doc.text(doc.at(item, "source")),
            doc.text(doc.at(item, "name")),
        )
        index += 1
    var body = out.new_dict()
    out.set(body, "replacements", replacements)
    out.set(body, "declarations", requests)
    var saved = out.root
    out.root = body
    var text = out.dumps()
    out.root = saved
    var prepared = lane_control_prepare(text)
    var end = prepared.byte_length() - 1
    var head = prepared[byte=0:end]
    return String(head) + ',"labels":' + labels_text + "}"
