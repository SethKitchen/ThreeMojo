# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every lane-control declaration in one check.

The caller supplies each source and function name. This check returns
the declaration texts in that order.
"""

from tests._python_tokens import declaration_text
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
