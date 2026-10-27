# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every stored-moment scalar word.

The caller supplies each scalar source and its pinned word. This check
returns the binary64 words in the same order.
"""

from tests._python_tokens import constant_literals_json
from tools._moment_guards import require_same_count
from tools._python_json import PyJson
from tools._spiral_moment_words import hex_integers_json, require_stored_words
from tools.carla_cleanup_gate import decimal_words_json


def _one_literal(source: String, name: String) raises -> String:
    """Return one scalar's decimal spelling.

    Args:
        source: The module source.
        name: The scalar name.

    Returns:
        The literal spelling.

    Raises:
        Error: The declaration changed. The text starts with
            `stored scalar literal: `.
    """
    try:
        var encoded = constant_literals_json(source, name, "scalar", 0)
        var parsed = PyJson.parse(encoded)
        return parsed.text(parsed.item(parsed.root, 0))
    except error:
        raise Error("stored scalar literal: " + name + "\n" + String(error))


def moment_scalars(payload: String) raises -> String:
    """Read and check a list of stored scalars.

    Args:
        payload: A JSON object with `items` and `overflow`. Each item has
            `name`, `source`, `expected`, and `message`. `expected` is the
            pinned `0x` word. `message` is the mismatch text. `overflow`
            is the text used when the word count disagrees.

    Returns:
        A JSON object. Each key is a scalar name and each value is a
        one-word list of unsigned decimal words.

    Raises:
        Error: A scalar declaration changed, a literal does not fit, or a
            stored word changed. A declaration error starts with
            `stored scalar literal: `.
    """
    var doc = PyJson.parse(payload)
    var items = doc.at(doc.root, "items")
    var overflow = doc.text(doc.at(doc.root, "overflow"))
    var count = doc.length(items)
    var literals = PyJson()
    var spellings = literals.new_list()
    var index = 0
    while index < count:
        var item = doc.item(items, index)
        var name = doc.text(doc.at(item, "name"))
        literals.append(
            spellings,
            literals.new_str(
                _one_literal(doc.text(doc.at(item, "source")), name)
            ),
        )
        index += 1
    literals.root = spellings
    var decoded = hex_integers_json(decimal_words_json(literals.dumps()))
    var parsed = PyJson.parse(decoded)
    var word_count = parsed.length(parsed.root)
    var guard = PyJson()
    var guard_body = guard.new_dict()
    guard.set(guard_body, "left", guard.new_int(word_count))
    guard.set(guard_body, "right", guard.new_int(count))
    guard.set(guard_body, "message", guard.new_str(overflow))
    guard.root = guard_body
    require_same_count(guard.dumps())
    var out = PyJson()
    var result = out.new_dict()
    index = 0
    while index < count:
        var item = doc.item(items, index)
        var name = doc.text(doc.at(item, "name"))
        var gate = PyJson()
        var body = gate.new_dict()
        var word_rows = gate.new_list()
        gate.append(
            word_rows,
            gate.new_str(parsed.text(parsed.item(parsed.root, index))),
        )
        gate.set(body, "words", word_rows)
        var expect_rows = gate.new_list()
        gate.append(
            expect_rows, gate.new_str(doc.text(doc.at(item, "expected")))
        )
        gate.set(body, "expected", expect_rows)
        gate.set(
            body, "message", gate.new_str(doc.text(doc.at(item, "message")))
        )
        gate.root = body
        require_stored_words(gate.dumps())
        var stored = out.new_list()
        out.append(
            stored, out.new_str(parsed.text(parsed.item(parsed.root, index)))
        )
        out.set(result, name, stored)
        index += 1
    out.root = result
    return out.dumps()
