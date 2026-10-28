# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Read one run declaration, then check its lane-search edges.

The declaration check removes postfix move sigils. The search checks use
that declaration. A move failure stops before the search checks.
"""

from tests._python_expr import require_fragment_checks
from tests._python_tokens import semantic_declaration
from tools._optional_runtime_edges import search_edge_payload
from tools._optional_runtime_messages import (
    prefix_fragment_error,
    prefix_move_error,
)


def search_edges_after_declaration(source: String, name: String) raises:
    """Read one declaration, then check its search edges.

    Args:
        source: The module text.
        name: The run function name.

    Raises:
        Error: The declaration cannot be read, or a search edge fails.
            A move failure keeps the contract prefix. A fragment failure
            keeps the contract prefix. The declaration is read first.
    """
    try:
        require_fragment_checks(
            search_edge_payload(
                semantic_declaration(source, name), name, "search"
            )
        )
    except error:
        var message = prefix_move_error(String(error))
        raise Error(prefix_fragment_error(message))
