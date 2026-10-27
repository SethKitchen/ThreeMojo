# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Compare kept-token digests in one check.

The caller supplies two sources, or one source and a pinned digest.
"""

from tests._python_tokens import token_sha256
from tools._python_json import MISSING, PyJson


def token_digest_match(payload: String) raises -> String:
    """Return whether kept-token digests agree.

    Args:
        payload: JSON with `left` and `right`, or with `text` and
            `digest`. `digest` is a hex SHA-256.

    Returns:
        `true` when the digests agree, otherwise `false`.

    Raises:
        Error: A required field is absent, or a source cannot be tokenized.
    """
    var doc = PyJson.parse(payload)
    var digest = doc.get(doc.root, "digest")
    if digest == MISSING:
        var left = token_sha256(doc.text(doc.at(doc.root, "left")))
        var right = token_sha256(doc.text(doc.at(doc.root, "right")))
        if left == right:
            return "true"
        return "false"
    var actual = token_sha256(doc.text(doc.at(doc.root, "text")))
    if actual == doc.text(digest):
        return "true"
    return "false"
