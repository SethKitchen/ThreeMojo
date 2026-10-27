# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check trig and geometry stored words.

    carla_cleanup_words PATH

`PATH` is a JSON list. Each item has `text`, `kind`, and `label`. The
program checks those word lists in order.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools.carla_cleanup_gate import cleanup_words_all


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_cleanup_words PATH", file=stderr)
    exit(2)


def main() raises:
    """Check every stored-word list and print nothing on success.

    Raises:
        Error: The command is invalid, or a word list changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        cleanup_words_all(Path(arguments[1]).read_text())
    except error:
        print(String(error), file=stderr)
        exit(1)
