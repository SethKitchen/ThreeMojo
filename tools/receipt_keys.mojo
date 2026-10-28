# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Refuse a repeated key in a coverage receipt.

    receipt_keys PATH

The program checks the file it is given. It does not read the repository.
A repeated key is reported as `Duplicate receipt key`. Invalid JSON uses
the parser text.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._duplicate_pin_keys import reject_duplicate_pin_keys


def receipt_keys(payload: Span[UInt8, _]) raises:
    """Refuse a repeated key in a coverage receipt.

    Args:
        payload: The receipt bytes.

    Raises:
        Error: A key is repeated, or the bytes are not JSON. The repeated
            key is `Duplicate receipt key`. Invalid JSON uses the parser text.
    """
    try:
        reject_duplicate_pin_keys(payload)
    except error:
        var message = String(error)
        var old = "duplicate runtime source pin key:"
        if message.startswith(old):
            var rest = message[byte=old.byte_length():]
            raise Error("Duplicate receipt key:" + rest)
        raise error


def _usage():
    """Print the command usage and stop."""
    print("usage: receipt_keys PATH", file=stderr)
    exit(2)


def main() raises:
    """Check one receipt file.

    Raises:
        Error: The command is invalid.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    try:
        receipt_keys(Path(arguments[1]).read_bytes())
    except error:
        print(String(error), file=stderr)
        exit(1)
