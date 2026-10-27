# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Compare kept-token digests.

    carla_token_digest PATH

PATH is JSON with `left` and `right`, or with `text` and `digest`.
The command prints `true` or `false`.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._token_digest import token_digest_match


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_token_digest PATH", file=stderr)
    exit(2)


def main() raises:
    """Print whether the kept-token digests agree.

    Raises:
        Error: The command is invalid, or a source cannot be tokenized.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        print(token_digest_match(Path(arguments[1]).read_text()), end="")
    except error:
        print(String(error), file=stderr)
        exit(1)
