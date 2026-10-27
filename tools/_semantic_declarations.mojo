# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every semantic declaration in one group.

The caller supplies each function and its module text. This check returns
the declarations with postfix move sigils removed.
"""

from tests._python_tokens import semantic_declaration
from tools._python_json import PyJson


def semantic_declarations(payload: String) raises -> String:
    """Return one declaration for each requested function.

    Args:
        payload: A JSON list. Each item has `key`, `name`, and `source`.

    Returns:
        A JSON object. Each key is the item key and each value is its
        declaration text.

    Raises:
        Error: A function is missing, or a `^` is not a move sigil.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var result = out.new_dict()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var key = doc.text(doc.at(item, "key"))
        out.set(
            result,
            key,
            out.new_str(
                semantic_declaration(
                    doc.text(doc.at(item, "source")),
                    doc.text(doc.at(item, "name")),
                )
            ),
        )
        index += 1
    out.root = result
    return out.dumps()
