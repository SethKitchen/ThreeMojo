# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Choose the dispatch source and compare one premise text.

An unchanged token keeps the current source. Only the sample-dispatch
module may restore its predecessor. Premise texts compare as Python
strings.
"""

from tools._python_json import PyJson


def reviewed_source_choice(payload: String) raises -> String:
    """Return whether to keep the current source or restore the predecessor.

    Args:
        payload: JSON with `token`, `expected`, `path`, and `dispatch_path`.

    Returns:
        `current` when the token matches. `restore` when it does not and
        `path` is the sample-dispatch module.

    Raises:
        Error: The token changed and the path is not the sample-dispatch
            module.
    """
    var doc = PyJson.parse(payload)
    if doc.text(doc.at(doc.root, "token")) == doc.text(
        doc.at(doc.root, "expected")
    ):
        return "current"
    var path = doc.text(doc.at(doc.root, "path"))
    if path == doc.text(doc.at(doc.root, "dispatch_path")):
        return "restore"
    raise Error(
        "curve support/dispatch contract: unreviewed source successor: " + path
    )


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
