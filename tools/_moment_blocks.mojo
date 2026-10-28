# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check every stored-moment operation block.

The caller supplies each block's source and pin. This check returns the
normalized block text in the same order. A combined check reads those
blocks before the route digests.
"""

from tests._python_tokens import require_operation_block
from tools._moment_routes import moment_route_digests
from tools._python_json import PyJson


def moment_blocks(payload: String) raises -> String:
    """Check a list of operation blocks.

    Args:
        payload: A JSON list. Each item has `name`, `source`, `begin`,
            `end`, `expected`, and `digest`.

    Returns:
        A JSON object. Each key is a block name and each value is its
        normalized text.

    Raises:
        Error: A pin digest disagrees, a live block changed, or a marker
            is invalid.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var result = out.new_dict()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var name = doc.text(doc.at(item, "name"))
        out.set(
            result,
            name,
            out.new_str(
                require_operation_block(
                    doc.text(doc.at(item, "source")),
                    doc.text(doc.at(item, "begin")),
                    doc.text(doc.at(item, "end")),
                    doc.text(doc.at(item, "expected")),
                    doc.text(doc.at(item, "digest")),
                    name,
                )
            ),
        )
        index += 1
    out.root = result
    return out.dumps()


def moment_blocks_and_digests(payload: String) raises -> String:
    """Check every operation block, then every route digest.

    Args:
        payload: JSON with `blocks` and `digests`. `blocks` is the
            operation-block list. `digests` is the route-digest list.

    Returns:
        The normalized blocks. Each key is a block name.

    Raises:
        Error: A block pin changed, or a route digest disagrees. A block
            error is raised before any digest is checked.
    """
    var doc = PyJson.parse(payload)
    var blocks_text = moment_blocks(
        doc.subtree(doc.at(doc.root, "blocks")).dumps()
    )
    moment_route_digests(doc.subtree(doc.at(doc.root, "digests")).dumps())
    return blocks_text
