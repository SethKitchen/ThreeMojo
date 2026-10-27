# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Group stored-moment fraction texts by array.

The caller supplies each array's binary64 words. This check returns the
exact fraction spelling of every word, in that array order.
"""

from tools._moment_guards import require_same_count
from tools._python_json import PyJson
from tools._spiral_moment_words import fraction_texts_payload, hex_words_json


def moment_fraction_groups(payload: String) raises -> String:
    """Return exact fraction spellings for each stored array.

    Args:
        payload: A JSON object with `groups` and `invalid`. Each group has
            `name` and `words`. `words` are unsigned decimal binary64
            encodings. `invalid` is the text used when the spelling count
            disagrees.

    Returns:
        A JSON object. Each key is an array name and each value is its
        `n` or `n/d` spellings.

    Raises:
        Error: A word is malformed or not finite, or the spelling count
            disagrees.
    """
    var doc = PyJson.parse(payload)
    var groups = doc.at(doc.root, "groups")
    var invalid = doc.text(doc.at(doc.root, "invalid"))
    var count = doc.length(groups)
    var flat = PyJson()
    var words = flat.new_list()
    var names = List[String]()
    var sizes = List[Int]()
    var index = 0
    var total = 0
    while index < count:
        var group = doc.item(groups, index)
        names.append(doc.text(doc.at(group, "name")))
        var row = doc.at(group, "words")
        var size = doc.length(row)
        sizes.append(size)
        var cursor = 0
        while cursor < size:
            flat.append(words, flat.new_str(doc.text(doc.item(row, cursor))))
            cursor += 1
        total += size
        index += 1
    flat.root = words
    var parsed = PyJson.parse(
        fraction_texts_payload(hex_words_json(flat.dumps()))
    )
    var guard = PyJson()
    var guard_body = guard.new_dict()
    guard.set(guard_body, "left", guard.new_int(parsed.length(parsed.root)))
    guard.set(guard_body, "right", guard.new_int(total))
    guard.set(guard_body, "message", guard.new_str(invalid))
    guard.root = guard_body
    require_same_count(guard.dumps())
    var out = PyJson()
    var result = out.new_dict()
    var cursor = 0
    index = 0
    while index < count:
        var name = names[index]
        var stored = out.new_list()
        var end = cursor + sizes[index]
        while cursor < end:
            out.append(
                stored,
                out.new_str(parsed.text(parsed.item(parsed.root, cursor))),
            )
            cursor += 1
        out.set(result, name, stored)
        index += 1
    out.root = result
    return out.dumps()
