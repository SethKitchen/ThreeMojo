# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check a list of optional-runtime fragments.

    carla_fragment_checks PATH

`PATH` is a JSON list of fragment checks. The program prints nothing
when every count matches.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_expr import require_fragment_checks
from tools._optional_runtime_messages import prefix_fragment_error


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_fragment_checks PATH", file=stderr)
    exit(2)


def main() raises:
    """Check one list of fragment counts.

    Raises:
        Error: The command is invalid, or a fragment count differs.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        require_fragment_checks(Path(arguments[1]).read_text())
    except error:
        print(prefix_fragment_error(String(error)), file=stderr)
        exit(1)
