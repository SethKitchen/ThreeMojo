# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every stored-moment constant array.

The caller supplies each array source and its pinned words. This check
returns the binary64 words in the same order.
"""

from tests._python_tokens import constant_literals_json
from tools._python_json import PyJson
from tools._spiral_moment_words import hex_integers_json, require_stored_words
from tools.carla_cleanup_gate import decimal_words_json


def _literals(source: String, name: String, size: Int) raises -> String:
    """Return one array's decimal literals.

    Args:
        source: The module source.
        name: The array name.
        size: The array length.

    Returns:
        A JSON list of literal spellings.

    Raises:
        Error: The declaration changed. The text starts with
            `stored array literal: `.
    """
    try:
        return constant_literals_json(source, name, "array", size)
    except error:
        raise Error("stored array literal: " + name + "\n" + String(error))


def moment_arrays(payload: String) raises -> String:
    """Read and check a list of stored arrays.

    Args:
        payload: A JSON list. Each item has `name`, `source`, `size`,
            `expected`, and `message`. `expected` is the pinned `0x` list.
            `message` is the mismatch text.

    Returns:
        A JSON object. Each key is an array name and each value is its
        unsigned decimal words.

    Raises:
        Error: An array declaration changed, a literal does not fit, or a
            stored word changed. A declaration error starts with
            `stored array literal: `.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var result = out.new_dict()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var name = doc.text(doc.at(item, "name"))
        var literals = _literals(
            doc.text(doc.at(item, "source")),
            name,
            Int(doc.text(doc.at(item, "size"))),
        )
        var hex_words = decimal_words_json(literals)
        var words = hex_integers_json(hex_words)
        var parsed = PyJson.parse(words)
        var gate = PyJson()
        var body = gate.new_dict()
        var word_rows = gate.new_list()
        var word_count = parsed.length(parsed.root)
        var cursor = 0
        while cursor < word_count:
            gate.append(
                word_rows,
                gate.new_str(parsed.text(parsed.item(parsed.root, cursor))),
            )
            cursor += 1
        gate.set(body, "words", word_rows)
        var expect_rows = gate.new_list()
        var expected = doc.at(item, "expected")
        var expect_count = doc.length(expected)
        cursor = 0
        while cursor < expect_count:
            gate.append(
                expect_rows,
                gate.new_str(doc.text(doc.item(expected, cursor))),
            )
            cursor += 1
        gate.set(body, "expected", expect_rows)
        gate.set(
            body, "message", gate.new_str(doc.text(doc.at(item, "message")))
        )
        gate.root = body
        require_stored_words(gate.dumps())
        var stored = out.new_list()
        cursor = 0
        while cursor < word_count:
            out.append(
                stored,
                out.new_str(parsed.text(parsed.item(parsed.root, cursor))),
            )
            cursor += 1
        out.set(result, name, stored)
        index += 1
    out.root = result
    return out.dumps()
