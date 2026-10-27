# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the frozen ARC producer record.

    carla_frozen_arc_gate --migration PATH [--previous PATH]

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
An absent previous file checks only the migration record.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import MISSING, PY_DICT, PY_INT, PY_STR, PyJson
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "70091e23400193257514363570187b47890e3c08c352fe79eb08bf291737cc9f"
)
comptime _SOURCE = "extensions/carla/curve_frozen_arc.mojo"


def _fail(message: String) raises:
    """Raise one frozen-ARC failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("frozen ARC producer contract: " + message)


def _require_record(doc: PyJson) raises:
    """Require schema 1.

    Args:
        doc: The migration record.

    Raises:
        Error: The schema changed.
    """
    var schema = doc.get(doc.root, "schema")
    if (
        schema == MISSING
        or doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
    ):
        _fail("unsupported migration schema")


def _require_previous(doc: PyJson, previous: Span[UInt8, _]) raises:
    """Require the cleanup digest and the successor path.

    Args:
        doc: The migration record.
        previous: The historical cleanup migration bytes.

    Raises:
        Error: The digest or the successor path changed.
    """
    var field = doc.get(doc.root, "previous_cleanup_migration_sha256")
    if (
        field == MISSING
        or doc.kind(field) != PY_STR
        or doc.text(field) != sha256_hex(previous)
    ):
        _fail("historical three-file cleanup changed")
    var successor = doc.get(doc.root, "source_successor")
    if successor == MISSING or doc.kind(successor) != PY_DICT:
        _fail("wrong successor source")
    var path = doc.get(successor, "path")
    if path == MISSING or doc.kind(path) != PY_STR or doc.text(path) != _SOURCE:
        _fail("wrong successor source")


def frozen_arc_record(
    migration: Span[UInt8, _],
    previous: Span[UInt8, _],
    check_previous: Bool,
) raises:
    """Require the frozen ARC producer record.

    Args:
        migration: The successor record bytes.
        previous: The historical cleanup migration. Used only when `check_previous` is true.
        check_previous: Whether to check the cleanup digest and the successor path.

    Raises:
        Error: The record, the cleanup digest, or the successor path changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    _require_record(doc)
    if not check_previous:
        return
    _require_previous(doc, previous)


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_frozen_arc_gate --migration PATH [--previous PATH]",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the frozen ARC record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var previous = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--migration" or word == "--previous":
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            else:
                previous = value
            index += 2
            continue
        _usage()
    if migration.byte_length() == 0:
        _usage()
    try:
        if previous.byte_length() == 0:
            frozen_arc_record(
                Path(migration).read_bytes(), String("").as_bytes(), False
            )
        else:
            frozen_arc_record(
                Path(migration).read_bytes(),
                Path(previous).read_bytes(),
                True,
            )
    except error:
        print(String(error), file=stderr)
        exit(1)
