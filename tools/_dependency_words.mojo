# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the reviewed stored-word check for one dependency.

An exact token match needs no word check. Only the reviewed trig and
geometry tokens may differ and still keep their stored words.
"""

from tests._python_tokens import token_sha256
from tools._python_json import MISSING, PyJson


def _word_choice(doc: PyJson, node: Int) raises -> String:
    """Return the word check for one dependency object.

    Args:
        doc: The parsed document.
        node: One dependency object.

    Returns:
        `match` when the token is unchanged, `trig` for the trig word
        check, or `geometry` for the geometry word check.

    Raises:
        Error: The path is not one of those reviewed token pairs.
    """
    var token_node = doc.get(node, "token")
    var token: String
    if token_node == MISSING:
        token = token_sha256(doc.text(doc.at(node, "text")))
    else:
        token = doc.text(token_node)
    var expected = doc.text(doc.at(node, "expected"))
    if token == expected:
        return "match"
    var path = doc.text(doc.at(node, "path"))
    if path == doc.text(doc.at(node, "trig_path")) and expected == doc.text(
        doc.at(node, "trig_token")
    ):
        return "trig"
    if path == doc.text(doc.at(node, "geometry_path")) and expected == doc.text(
        doc.at(node, "geometry_token")
    ):
        return "geometry"
    raise Error(
        "reviewed cleanup source contract: unchanged premise dependency"
        " changed: "
        + path
    )


def dependency_word_choice(payload: String) raises -> String:
    """Return which stored-word check a dependency needs.

    Args:
        payload: JSON with `expected`, `path`, `trig_path`, `trig_token`,
            `geometry_path`, and `geometry_token`. `token` is the current
            digest. `text` is hashed when `token` is absent.

    Returns:
        `match` when the token is unchanged, `trig` for the trig word
        check, or `geometry` for the geometry word check.

    Raises:
        Error: The path is not one of those reviewed token pairs.
    """
    var doc = PyJson.parse(payload)
    return _word_choice(doc, doc.root)


def dependency_word_choices(payload: String) raises -> String:
    """Return the word check for each dependency.

    Args:
        payload: A JSON list. Each item has the choice fields.

    Returns:
        A JSON list of `match`, `trig`, or `geometry`, in the same order.

    Raises:
        Error: A dependency is not one of those reviewed token pairs.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var rows = out.new_list()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        out.append(
            rows, out.new_str(_word_choice(doc, doc.item(doc.root, index)))
        )
        index += 1
    out.root = rows
    return out.dumps()
