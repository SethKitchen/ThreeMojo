# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the Map seed or lane predecessor after a premise comparison."""

from tools._python_json import PY_BOOL, PY_LIST, PyJson


def _is_true(doc: PyJson, key: String) raises -> Bool:
    """Return whether a field is JSON true.

    Args:
        doc: The decision document.
        key: The field name.

    Returns:
        True only for a boolean true. Every other kind is false.
    """
    var node = doc.at(doc.root, key)
    return doc.kind(node) == PY_BOOL and doc.flag(node)


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
    if _is_true(doc, "matched"):
        return "none"
    var path = doc.text(doc.at(doc.root, "path"))
    var name = doc.text(doc.at(doc.root, "name"))
    var owner = doc.at(doc.root, "owner")
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
