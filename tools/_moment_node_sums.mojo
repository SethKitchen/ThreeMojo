# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the rounded stored-moment node sums.

The caller supplies the stored node and weight words. This check returns
the exact fraction spelling of each rounded `1 + node` word.
"""

from tools._python_json import PyJson
from tools._spiral_moment_words import (
    fraction_texts_payload,
    hex_integers_json,
    hex_words_json,
    require_stored_words,
    rounded_node_sums_payload,
)


def _list_json(doc: PyJson, node: Int) raises -> String:
    """Return one JSON list copied from `node`.

    Args:
        doc: The source document.
        node: A list of strings.

    Returns:
        A JSON list with the same strings.

    Raises:
        Error: An item cannot be read.
    """
    var out = PyJson()
    var rows = out.new_list()
    var count = doc.length(node)
    var index = 0
    while index < count:
        out.append(rows, out.new_str(doc.text(doc.item(node, index))))
        index += 1
    out.root = rows
    return out.dumps()


def _copy_list(mut destination: PyJson, rows: Int, encoded: String) raises:
    """Copy a JSON string list into `rows`.

    Args:
        destination: The document that owns `rows`.
        rows: The destination list.
        encoded: A JSON list of strings.

    Raises:
        Error: An item cannot be read.
    """
    var parsed = PyJson.parse(encoded)
    var count = parsed.length(parsed.root)
    var index = 0
    while index < count:
        destination.append(
            rows,
            destination.new_str(parsed.text(parsed.item(parsed.root, index))),
        )
        index += 1


def moment_node_sums(payload: String) raises -> String:
    """Check the rounded `1 + node` words and spell them as fractions.

    Args:
        payload: A JSON object with `nodes`, `weights`, `expected`, and
            `message`. `nodes` and `weights` are unsigned decimal words.
            `expected` is the pinned `0x` list. `message` is the mismatch
            text.

    Returns:
        A JSON list of `n` or `n/d` spellings, in node order.

    Raises:
        Error: A word is invalid, the lists do not hold five words, the
            weights do not keep the zeroth moment, or a sum changed.
    """
    var doc = PyJson.parse(payload)
    var sums_input = PyJson()
    var body = sums_input.new_dict()
    var node_rows = sums_input.new_list()
    var weight_rows = sums_input.new_list()
    _copy_list(
        sums_input,
        node_rows,
        hex_words_json(_list_json(doc, doc.at(doc.root, "nodes"))),
    )
    _copy_list(
        sums_input,
        weight_rows,
        hex_words_json(_list_json(doc, doc.at(doc.root, "weights"))),
    )
    sums_input.set(body, "nodes", node_rows)
    sums_input.set(body, "weights", weight_rows)
    sums_input.root = body
    var sums_hex = rounded_node_sums_payload(sums_input.dumps())
    var decimals = PyJson.parse(hex_integers_json(sums_hex))
    var gate = PyJson()
    var gate_body = gate.new_dict()
    var word_rows = gate.new_list()
    _copy_list(gate, word_rows, decimals.dumps())
    gate.set(gate_body, "words", word_rows)
    var expect_rows = gate.new_list()
    _copy_list(gate, expect_rows, _list_json(doc, doc.at(doc.root, "expected")))
    gate.set(gate_body, "expected", expect_rows)
    gate.set(
        gate_body,
        "message",
        gate.new_str(doc.text(doc.at(doc.root, "message"))),
    )
    gate.root = gate_body
    require_stored_words(gate.dumps())
    return fraction_texts_payload(sums_hex)
