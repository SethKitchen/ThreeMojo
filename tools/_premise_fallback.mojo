# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the Map seed or lane predecessor after a premise comparison."""

from tools._python_json import PY_BOOL, PY_LIST, PyJson


def _is_true(doc: PyJson, node: Int) -> Bool:
    """Return whether a value is JSON true.

    Args:
        doc: The decision document.
        node: The value.

    Returns:
        True only for a boolean true. Every other kind is false.
    """
    return doc.kind(node) == PY_BOOL and doc.flag(node)


def _choice(doc: PyJson, node: Int) raises -> String:
    """Choose one premise predecessor.

    Args:
        doc: The parsed document.
        node: One premise object.

    Returns:
        `none`, `seed`, or `lane`.

    Raises:
        Error: A required field is missing.
    """
    if _is_true(doc, doc.at(node, "matched")):
        return "none"
    var path = doc.text(doc.at(node, "path"))
    var name = doc.text(doc.at(node, "name"))
    var owner = doc.at(node, "owner")
    var empty_owner = doc.kind(owner) == PY_LIST and doc.length(owner) == 0
    if (
        path == "extensions/carla/map.mojo"
        and name == "_try_winner_seed"
        and empty_owner
    ):
        return "seed"
    if path == "extensions/carla/lane_refinement.mojo":
        return "lane"
    return "none"


def premise_fallback(payload: String) raises -> String:
    """Choose the predecessor used when a premise text differs.

    Args:
        payload: JSON with `matched`, `path`, `name`, and `owner`. `owner`
            is the enclosing names from the outside inward.

    Returns:
        `none` when the texts match or no reviewed predecessor applies.
        `seed` for the empty-owner Map winner seed. `lane` for the lane
        refinement module.

    Raises:
        Error: A required field is missing.
    """
    var doc = PyJson.parse(payload)
    return _choice(doc, doc.root)


def premise_fallbacks(payload: String) raises -> String:
    """Choose the predecessor for each premise.

    Args:
        payload: A JSON list. Each item has `matched`, `path`, `name`, and
            `owner`.

    Returns:
        A JSON list of `none`, `seed`, or `lane`, in the same order.

    Raises:
        Error: A required field is missing.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var rows = out.new_list()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        out.append(rows, out.new_str(_choice(doc, doc.item(doc.root, index))))
        index += 1
    out.root = rows
    return out.dumps()
