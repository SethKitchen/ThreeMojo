# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Decide whether one lane declaration is the reviewed predecessor.

An owned declaration is refused. A matching path and name must keep the
same token digest.
"""

from tests._python_tokens import token_sha256
from tools._python_json import PyJson


def accept_lane_predecessor(payload: String) raises -> String:
    """Return whether the expected source is the reviewed predecessor.

    Args:
        payload: JSON with `owner`, `path`, `name`, `expected`, and
            `declarations`. Each declaration has `path`, `name`, and
            `before`.

    Returns:
        `true` when `owner` is empty, one declaration matches, and the
        token digests match. Otherwise `false`.

    Raises:
        Error: A declaration cannot be read.
    """
    var doc = PyJson.parse(payload)
    if doc.length(doc.at(doc.root, "owner")) > 0:
        return "false"
    var path = doc.text(doc.at(doc.root, "path"))
    var name = doc.text(doc.at(doc.root, "name"))
    var declarations = doc.at(doc.root, "declarations")
    var count = doc.length(declarations)
    var index = 0
    while index < count:
        var item = doc.item(declarations, index)
        if (
            doc.text(doc.at(item, "path")) == path
            and doc.text(doc.at(item, "name")) == name
        ):
            var expected = token_sha256(doc.text(doc.at(doc.root, "expected")))
            var before = token_sha256(doc.text(doc.at(item, "before")))
            if expected == before:
                return "true"
            return "false"
        index += 1
    return "false"


def _is_minimum(doc: PyJson, node: Int) raises -> String:
    """Return whether one declaration is the rounded lane minimum.

    Args:
        doc: The parsed document.
        node: One declaration object.

    Returns:
        `true` when the path is `extensions/carla/lane_refinement.mojo`,
        the name is `_rounded_axis_lane_minimum`, and `owner` is empty.
        Otherwise `false`.

    Raises:
        Error: A field is absent.
    """
    var path = doc.text(doc.at(node, "path"))
    var name = doc.text(doc.at(node, "name"))
    var owner = doc.at(node, "owner")
    if (
        path == "extensions/carla/lane_refinement.mojo"
        and name == "_rounded_axis_lane_minimum"
        and doc.length(owner) == 0
    ):
        return "true"
    return "false"


def selected_lane_minimum(payload: String) raises -> String:
    """Return whether this declaration is the rounded lane minimum.

    Args:
        payload: JSON with `path`, `name`, and `owner`.

    Returns:
        `true` when the path is `extensions/carla/lane_refinement.mojo`,
        the name is `_rounded_axis_lane_minimum`, and `owner` is empty.
        Otherwise `false`.

    Raises:
        Error: A field is absent.
    """
    var doc = PyJson.parse(payload)
    return _is_minimum(doc, doc.root)


def selected_lane_minima(payload: String) raises -> String:
    """Return whether each declaration is the rounded lane minimum.

    Args:
        payload: A JSON list. Each item has `path`, `name`, and `owner`.

    Returns:
        A JSON list of `true` or `false`, in the same order.

    Raises:
        Error: A field is absent.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var rows = out.new_list()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        out.append(
            rows, out.new_str(_is_minimum(doc, doc.item(doc.root, index)))
        )
        index += 1
    out.root = rows
    return out.dumps()
