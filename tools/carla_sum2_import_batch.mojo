# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the Sum2 helper imports and the stored-half function.

    carla_sum2_import_batch PATH

PATH is JSON with `texts` and `interval`. The command checks the three
helper imports, requires `_stored_half`, then checks that import.
It prints nothing when they match.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._sum2_helper_bindings import sum2_import_batch


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_sum2_import_batch PATH", file=stderr)
    exit(2)


def main() raises:
    """Check the Sum2 imports and the stored-half function.

    Raises:
        Error: The command is invalid, or an import or function changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        sum2_import_batch(Path(arguments[1]).read_text())
    except error:
        print(String(error), file=stderr)
        exit(1)
