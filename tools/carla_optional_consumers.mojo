# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check observed containing-model consumers.

    carla_optional_consumers PATH

`PATH` is a JSON list of `path` and `text` objects. The program prints
nothing when the observed modules keep the reviewed names out.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._optional_model_consumers import require_observed_consumers


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_optional_consumers PATH", file=stderr)
    exit(2)


def main() raises:
    """Check one list of observed modules.

    Raises:
        Error: The command is invalid, or a module names a reviewed helper.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        require_observed_consumers(Path(arguments[1]).read_text())
    except error:
        print(String(error), file=stderr)
        exit(1)
