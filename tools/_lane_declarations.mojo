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
    significant_json,
    token_sha256,
)
from tools._python_json import PyJson


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
