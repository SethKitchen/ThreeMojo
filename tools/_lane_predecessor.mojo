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
