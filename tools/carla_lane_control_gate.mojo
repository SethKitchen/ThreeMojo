# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the lane-control migration record.

    carla_lane_control_gate --migration PATH

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._python_json import MISSING, PY_STR, PyJson
from tools._sha256 import sha256_hex


comptime _RECORD_SHA256 = (
    "73d95d594e740205bad4cd900288a68d9f82897474fdc33e4d6043a156790170"
)
comptime _PREDECESSOR_SHA256 = (
    "33d33ba0e481e3eca3b17ae0d02457ab53bae906430b0dca58abcfa876756315"
)


def _fail(message: String) raises:
    """Raise one lane-control failure.

    Args:
        message: The complete failure text.

    Raises:
        Error: Always.
    """
    raise Error(message)


def _field(doc: PyJson, name: String) raises -> String:
    """Return one string field.

    Args:
        doc: The record.
        name: The field name.

    Returns:
        The field text.

    Raises:
        Error: The field is absent or is not a string.
    """
    var node = doc.get(doc.root, name)
    if node == MISSING or doc.kind(node) != PY_STR:
        _fail("lane-control predecessor changed")
    return doc.text(node)


def lane_control_record(migration: Span[UInt8, _]) raises:
    """Require the lane-control migration and its embedded sources.

    Args:
        migration: The successor record bytes.

    Raises:
        Error: The record digest or an embedded source digest changed.
    """
    if sha256_hex(migration) != _RECORD_SHA256:
        _fail("lane-control migration record changed")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var before = _field(doc, "before_source")
    var before_hash = _field(doc, "before_sha256")
    var digest = sha256_hex(before.as_bytes())
    if digest != before_hash or digest != _PREDECESSOR_SHA256:
        _fail("lane-control predecessor changed")
    var after = doc.get(doc.root, "after_source")
    var after_hash = doc.get(doc.root, "after_sha256")
    if (
        after == MISSING
        or doc.kind(after) != PY_STR
        or after_hash == MISSING
        or doc.kind(after_hash) != PY_STR
        or sha256_hex(doc.text(after).as_bytes()) != doc.text(after_hash)
    ):
        _fail("lane-control successor record changed")


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_lane_control_gate --migration PATH", file=stderr)
    exit(2)


def main() raises:
    """Check the lane-control record and print nothing on success.

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
        lane_control_record(Path(migration).read_bytes())
    except error:
        print(String(error), file=stderr)
        exit(1)
