# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the dispatch source and compare premise texts.

An unchanged token keeps the current source. Only the sample-dispatch
module may restore its predecessor. Premise texts compare as Python
strings.
"""

from tests._python_tokens import token_sha256
from tools._python_json import MISSING, PyJson


def reviewed_source_choice(payload: String) raises -> String:
    """Return whether to keep the current source or restore the predecessor.

    Args:
        payload: JSON with `expected`, `path`, and `dispatch_path`.
            `token` is the current digest. `text` is hashed when `token`
            is absent.

    Returns:
        `current` when the token matches. `restore` when it does not and
        `path` is the sample-dispatch module.

    Raises:
        Error: The token changed and the path is not the sample-dispatch
            module.
    """
    var doc = PyJson.parse(payload)
    return _source_choice(doc, doc.root)


def _source_choice(doc: PyJson, node: Int) raises -> String:
    """Return the choice for one source object.

    Args:
        doc: The parsed document.
        node: One source object.

    Returns:
        `current` when the token matches. `restore` when it does not and
        `path` is the sample-dispatch module.

    Raises:
        Error: The token changed and the path is not the sample-dispatch
            module.
    """
    var token_node = doc.get(node, "token")
    var token: String
    if token_node == MISSING:
        token = token_sha256(doc.text(doc.at(node, "text")))
    else:
        token = doc.text(token_node)
    if token == doc.text(doc.at(node, "expected")):
        return "current"
    var path = doc.text(doc.at(node, "path"))
    if path == doc.text(doc.at(node, "dispatch_path")):
        return "restore"
    raise Error(
        "curve support/dispatch contract: unreviewed source successor: " + path
    )


def reviewed_source_choices(payload: String) raises -> String:
    """Return the choice for each dispatch source.

    Args:
        payload: A JSON list. Each item has the choice fields.

    Returns:
        A JSON list of `current` or `restore`, in the same order.

    Raises:
        Error: A token changed outside the sample-dispatch module.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var rows = out.new_list()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        out.append(
            rows, out.new_str(_source_choice(doc, doc.item(doc.root, index)))
        )
        index += 1
    out.root = rows
    return out.dumps()


def texts_match(payload: String) raises -> String:
    """Return whether two texts are the same string.

    Args:
        payload: JSON with `actual` and `expected`.

    Returns:
        `true` when the texts are equal, otherwise `false`.

    Raises:
        Error: A text field is absent.
    """
    var doc = PyJson.parse(payload)
    if doc.text(doc.at(doc.root, "actual")) == doc.text(
        doc.at(doc.root, "expected")
    ):
        return "true"
    return "false"


def texts_match_all(payload: String) raises -> String:
    """Return whether each premise text matches.

    Args:
        payload: A JSON list. Each item has `actual` and `expected`.

    Returns:
        A JSON list of `true` or `false`, in the same order.

    Raises:
        Error: A text field is absent.
    """
    var doc = PyJson.parse(payload)
    var out = PyJson()
    var rows = out.new_list()
    var count = doc.length(doc.root)
    var index = 0
    while index < count:
        var item = doc.item(doc.root, index)
        var flag = String("false")
        if doc.text(doc.at(item, "actual")) == doc.text(
            doc.at(item, "expected")
        ):
            flag = "true"
        out.append(rows, out.new_str(flag))
        index += 1
    out.root = rows
    return out.dumps()
