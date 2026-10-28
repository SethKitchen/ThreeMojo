# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check one optional-runtime semantic fragment group.

    carla_semantic_edges GROUP PATH

`GROUP` names the check group. `PATH` is JSON with each declaration's
`source` and `name`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_expr import require_fragment_checks
from tools._optional_runtime_messages import prefix_fragment_error
from tools._semantic_edges import semantic_edge_payload


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_semantic_edges GROUP PATH", file=stderr)
    exit(2)


def main() raises:
    """Check one semantic fragment group.

    Raises:
        Error: The command is invalid, or a fragment check fails.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    try:
        require_fragment_checks(
            semantic_edge_payload(arguments[1], Path(arguments[2]).read_text())
        )
    except error:
        print(prefix_fragment_error(String(error)), file=stderr)
        exit(1)
