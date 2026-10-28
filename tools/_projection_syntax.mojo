# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Classify the copied helpers after the helper-name check.

The helper-name JSON already lists each copied source. This pass appends
a syntax list in that key order. A syntax failure stays in the list.
"""

from tools._python_json import PyJson
from tools.carla_cleanup_gate import classified_syntax_all


def append_helper_syntax(projected: String) raises -> String:
    """Classify each copied helper and append that syntax list.

    Args:
        projected: JSON from the helper-name check. `record.helpers`
            maps each sampled name to its source, in key order.

    Returns:
        The same JSON with `syntax` after the other fields. The list
        follows that key order. A syntax failure stays in the list.

    Raises:
        Error: The JSON is unreadable or the helper object is absent.
    """
    var parsed = PyJson.parse(projected)
    var helpers = parsed.at(parsed.at(parsed.root, "record"), "helpers")
    var count = parsed.length(helpers)
    var doc = PyJson()
    var rows = doc.new_list()
    var index = 0
    while index < count:
        var key = parsed.key(helpers, index)
        doc.append(rows, doc.new_str(parsed.text(parsed.at(helpers, key))))
        index += 1
    doc.root = rows
    var syntax = classified_syntax_all(doc.dumps())
    var end = projected.byte_length() - 1
    if end < 0:
        raise Error("sampled projection step changed")
    var prefix = projected[byte=0:end]
    return String(prefix) + ',"syntax":' + syntax + "}"
