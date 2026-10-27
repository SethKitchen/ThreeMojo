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
    var token_node = doc.get(doc.root, "token")
    var token: String
    if token_node == MISSING:
        token = token_sha256(doc.text(doc.at(doc.root, "text")))
    else:
        token = doc.text(token_node)
    var expected = doc.text(doc.at(doc.root, "expected"))
    if token == expected:
        return "match"
    var path = doc.text(doc.at(doc.root, "path"))
    if path == doc.text(doc.at(doc.root, "trig_path")) and expected == doc.text(
        doc.at(doc.root, "trig_token")
    ):
        return "trig"
    if path == doc.text(
        doc.at(doc.root, "geometry_path")
    ) and expected == doc.text(doc.at(doc.root, "geometry_token")):
        return "geometry"
    raise Error(
        "reviewed cleanup source contract: unchanged premise dependency"
        " changed: "
        + path
    )
