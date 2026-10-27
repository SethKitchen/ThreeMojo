# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the rounded LINE singleton migration record.

    carla_singleton_gate --migration PATH
    carla_singleton_gate --text PATH --decoded PATH

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._python_json import MISSING, PyJson, py_equal
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "e4a0eb6c9e527dd66b2b803ee69754334feecc9bea33ce001cdf584d3a693506"
)


def _fail(message: String) raises:
    """Raise one singleton-record failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("rounded LINE singleton contract: " + message)


def singleton_record(migration: Span[UInt8, _]) raises:
    """Require the rounded LINE singleton migration.

    Args:
        migration: The successor record bytes.

    Raises:
        Error: The digest or the schema changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var schema = doc.get(doc.root, "schema")
    var one = PyJson.parse("1")
    if schema == MISSING or not py_equal(doc, schema, one, one.root):
        _fail("wrong schema")


def singleton_views(text: String, decoded: String) raises:
    """Require the text view and the decoded byte view to share one token.

    Args:
        text: The text read from the lane source.
        decoded: The same file decoded from its bytes.

    Raises:
        Error: The token digests disagree.
    """
    if token_sha256(text) != token_sha256(decoded):
        _fail("consumer lane source text/bytes disagree")


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_singleton_gate --migration PATH"
            " | --text PATH --decoded PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the singleton record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var text = String("")
    var decoded = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--migration" or word == "--text" or word == "--decoded":
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--text":
                text = value
            else:
                decoded = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if text.byte_length() > 0 or decoded.byte_length() > 0:
        modes += 1
    if modes != 1 or (text.byte_length() == 0) != (decoded.byte_length() == 0):
        _usage()
    try:
        if text.byte_length() > 0:
            singleton_views(Path(text).read_text(), Path(decoded).read_text())
            return
        singleton_record(Path(migration).read_bytes())
    except error:
        print(String(error), file=stderr)
        exit(1)
