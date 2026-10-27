# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the reviewed cleanup migration record.

    carla_cleanup_gate --migration PATH [--previous PATH]

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
An absent previous file checks only the migration record.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import MISSING, PY_DICT, PY_INT, PY_STR, PyJson
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "01753344fe01d885eb3bbaf253815bca01816c57c09b6e7cc1c3a233808b42a9"
)


def _fail(message: String) raises:
    """Raise one reviewed-cleanup failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("reviewed cleanup source contract: " + message)


def _named(group: Int, index: Int) -> String:
    """Return one reviewed path.

    Args:
        group: 0 for successors, 1 for premise dependencies.
        index: The path position in that group.

    Returns:
        The repository path.
    """
    if group == 0:
        if index == 0:
            return "extensions/carla/curve_rounded_line.mojo"
        if index == 1:
            return "extensions/carla/curve_rounded_arc.mojo"
        return "extensions/carla/junction_bounds.mojo"
    if index == 0:
        return "extensions/carla/road_info.mojo"
    return "extensions/carla/curve_trig.mojo"


def _keys_match(doc: PyJson, node: Int, group: Int, count: Int) -> Bool:
    """Return whether an object has exactly one reviewed key set.

    Args:
        doc: The record.
        node: The object, or `MISSING`.
        group: Which reviewed path table to use.
        count: The number of reviewed paths.

    Returns:
        True when the keys are exactly that set.
    """
    if (
        node == MISSING
        or doc.kind(node) != PY_DICT
        or doc.length(node) != count
    ):
        return False
    var index = 0
    while index < count:
        if doc.get(node, _named(group, index)) == MISSING:
            return False
        index += 1
    return True


def _require_record(doc: PyJson) raises:
    """Require schema 1, the successor set, and the premise set.

    Args:
        doc: The migration record.

    Raises:
        Error: The schema or a path set changed.
    """
    var schema = doc.get(doc.root, "schema")
    if (
        schema == MISSING
        or doc.kind(schema) != PY_INT
        or doc.text(schema) != "1"
    ):
        _fail("unsupported migration schema")
    if not _keys_match(doc, doc.get(doc.root, "sources"), 0, 3):
        _fail("wrong successor set")
    if not _keys_match(doc, doc.get(doc.root, "premise_dependencies"), 1, 2):
        _fail("wrong premise dependency set")


def _require_previous(doc: PyJson, previous: Span[UInt8, _]) raises:
    """Require the winner-sign migration digest.

    Args:
        doc: The migration record.
        previous: The historical winner-sign migration bytes.

    Raises:
        Error: The digest changed.
    """
    var field = doc.get(doc.root, "prior_winner_sign_migration_sha256")
    if (
        field == MISSING
        or doc.kind(field) != PY_STR
        or doc.text(field) != sha256_hex(previous)
    ):
        _fail("historical winner/sign record changed")


def cleanup_record(
    migration: Span[UInt8, _],
    previous: Span[UInt8, _],
    check_previous: Bool,
) raises:
    """Require the reviewed cleanup record.

    Args:
        migration: The successor record bytes.
        previous: The winner-sign migration. Used only when `check_previous` is true.
        check_previous: Whether to check the winner-sign digest.

    Raises:
        Error: The record or the winner-sign digest changed.
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
        "usage: carla_cleanup_gate --migration PATH [--previous PATH]",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the reviewed cleanup record and print nothing on success.

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
            cleanup_record(
                Path(migration).read_bytes(), String("").as_bytes(), False
            )
        else:
            cleanup_record(
                Path(migration).read_bytes(), Path(previous).read_bytes(), True
            )
    except error:
        print(String(error), file=stderr)
        exit(1)
