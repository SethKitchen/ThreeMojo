# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the selection predecessor record.

    carla_selection_record_gate --migration PATH

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._sha256 import sha256_hex


comptime _RECORD_SHA256 = (
    "dcd2c780640775e29a566491679dc6fbf5ab1afa43fbfbae86cb778433cf92e8"
)


def selection_record(migration: Span[UInt8, _]) raises:
    """Require the selection predecessor record.

    Args:
        migration: The contract record bytes.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(migration) != _RECORD_SHA256:
        raise Error("Unreviewed selection predecessor record")


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_selection_record_gate --migration PATH", file=stderr)
    exit(2)


def main() raises:
    """Check the selection record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--migration":
            if index + 1 >= len(arguments):
                _usage()
            migration = arguments[index + 1]
            index += 2
            continue
        _usage()
    if migration.byte_length() == 0:
        _usage()
    try:
        selection_record(Path(migration).read_bytes())
    except error:
        print(String(error), file=stderr)
        exit(1)
