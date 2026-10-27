# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Build the ideal-projection result and require its source text."""

from tools._json_tools import quote_ascii
from tools._python_json import PY_STR, PyJson


def projection_result(digest: String) -> String:
    """Return the reviewed ideal-projection result record.

    Args:
        digest: The projected AST SHA-256.

    Returns:
        JSON for the eight result fields, in historical order.
    """
    var out = String('{"helper_projections":5,"rate_half_commutations":2')
    out += ',"projected_ast_sha256":'
    out += quote_ascii(digest)
    out += ',"sum2_auxiliary_declarations":4,"sum2_term_definitions":2'
    out += ',"sum2_auxiliary_updates":4,"sum2_error_writes":2'
    out += ',"sum2_environment_guards":1}'
    return out


def require_source_text(payload: String) raises:
    """Require one projection input to be a string.

    Args:
        payload: JSON with `text` and `message`.

    Raises:
        Error: `text` is not a string. The text is `message`.
    """
    var doc = PyJson.parse(payload)
    var text = doc.at(doc.root, "text")
    if doc.kind(text) != PY_STR:
        raise Error(doc.text(doc.at(doc.root, "message")))
