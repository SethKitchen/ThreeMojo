# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read every stored-moment constant array.

The caller supplies each array source and its pinned words. This check
returns the binary64 words in the same order.
"""

from tests._python_tokens import constant_literals_json
from tools._moment_fractions import moment_fraction_groups
from tools._moment_guards import require_name_set
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


def moment_array_fractions(payload: String) raises -> String:
    """Read every stored array, then its fraction spellings and its name set.

    Args:
        payload: JSON with `arrays`, `invalid`, `names`, and `message`.
            `arrays` is the stored-array list. `invalid` is the fraction
            count message. `names` is the required array-name list.

    Returns:
        JSON with `words` and `fractions`.

    Raises:
        Error: An array declaration changed, a fraction is not finite, or
            the array names differ.
    """
    var doc = PyJson.parse(payload)
    var words_text = moment_arrays(
        doc.subtree(doc.at(doc.root, "arrays")).dumps()
    )
    var words = PyJson.parse(words_text)
    var groups_doc = PyJson()
    var root = groups_doc.new_dict()
    var groups = groups_doc.new_list()
    var found = groups_doc.new_list()
    var count = words.length(words.root)
    var index = 0
    while index < count:
        var name = words.key(words.root, index)
        groups_doc.append(found, groups_doc.new_str(name))
        var row = groups_doc.new_dict()
        groups_doc.set(row, "name", groups_doc.new_str(name))
        var values = groups_doc.new_list()
        var stored = words.at(words.root, name)
        var size = words.length(stored)
        var cursor = 0
        while cursor < size:
            groups_doc.append(
                values,
                groups_doc.new_str(words.text(words.item(stored, cursor))),
            )
            cursor += 1
        groups_doc.set(row, "words", values)
        groups_doc.append(groups, row)
        index += 1
    groups_doc.set(root, "groups", groups)
    groups_doc.set(
        root,
        "invalid",
        groups_doc.new_str(doc.text(doc.at(doc.root, "invalid"))),
    )
    groups_doc.root = root
    var fractions_text = moment_fraction_groups(groups_doc.dumps())
    var names_doc = PyJson()
    var names_root = names_doc.new_dict()
    names_doc.set(names_root, "names", names_doc.adopt(groups_doc, found))
    var expected = names_doc.new_list()
    var wanted = doc.at(doc.root, "names")
    var name_count = doc.length(wanted)
    index = 0
    while index < name_count:
        names_doc.append(
            expected, names_doc.new_str(doc.text(doc.item(wanted, index)))
        )
        index += 1
    names_doc.set(names_root, "expected", expected)
    names_doc.set(
        names_root,
        "message",
        names_doc.new_str(doc.text(doc.at(doc.root, "message"))),
    )
    names_doc.root = names_root
    require_name_set(names_doc.dumps())
    return '{"words":' + words_text + ',"fractions":' + fractions_text + "}"
