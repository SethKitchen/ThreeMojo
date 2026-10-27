# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the raw-cut inverse record and its module token.

    carla_raw_cut_gate --migration PATH [--module PATH]
    carla_raw_cut_gate --predecessor PATH --sha HEX
    carla_raw_cut_gate --fixture PATH --token HEX

The program checks the texts it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._python_json import PY_BOOL, PY_INT, PyJson
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "4f4eb051d9c1f9194796d3073fcadfa9f49dda4c44a851da0a3409ba09587dd0"
)
comptime _SOURCE = "extensions/carla/curve_sample_dispatch.mojo"


def _fail(message: String) raises:
    """Raise one raw-cut failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("raw cut inverse contract: " + message)


def _schema_one(doc: PyJson) raises -> Bool:
    """Return whether the schema field is Python's `1`.

    Args:
        doc: The record.

    Returns:
        True for the integer 1 and for `True`.

    Raises:
        Error: The field is absent.
    """
    var schema = doc.at(doc.root, "schema")
    var kind = doc.kind(schema)
    if kind == PY_INT:
        return doc.text(schema) == "1"
    if kind == PY_BOOL:
        return doc.flag(schema)
    return False


def raw_cut_record(migration: Span[UInt8, _], module: String) raises:
    """Require the raw-cut record, and the live module when it is given.

    Args:
        migration: The successor record bytes.
        module: The historical dispatch source. Empty skips that check.

    Raises:
        Error: The record or the module token changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    if not _schema_one(doc) or doc.text(doc.at(doc.root, "path")) != _SOURCE:
        _fail("wrong successor source or schema")
    var before = doc.text(doc.at(doc.root, "before_source"))
    var after = doc.text(doc.at(doc.root, "after_source"))
    if token_sha256(before) != doc.text(
        doc.at(doc.root, "before_token_sha256")
    ) or token_sha256(after) != doc.text(
        doc.at(doc.root, "after_token_sha256")
    ):
        _fail("recorded source/token mismatch")
    if module.byte_length() == 0:
        return
    if token_sha256(module) != doc.text(doc.at(doc.root, "after_token_sha256")):
        _fail("complete raw inverse successor changed")


def raw_cut_digest(payload: Span[UInt8, _], expected: String) raises:
    """Require the historical predecessor migration digest.

    Args:
        payload: The predecessor migration bytes.
        expected: The required SHA-256 hex digest.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(payload) != expected:
        raise Error(
            "raw cut inverse contract: historical predecessor record changed"
        )


def raw_cut_fixture(text: String, expected: String) raises:
    """Require the native fixture token digest.

    Args:
        text: The fixture source.
        expected: The required token digest.

    Raises:
        Error: The token digest changed.
    """
    if token_sha256(text) != expected:
        _fail("independent exact-word native fixture changed")


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_raw_cut_gate --migration PATH [--module PATH]"
            " | --predecessor PATH --sha HEX | --fixture PATH --token HEX"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the raw-cut record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var module = String("")
    var predecessor = String("")
    var digest = String("")
    var fixture = String("")
    var token = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--module"
            or word == "--predecessor"
            or word == "--sha"
            or word == "--fixture"
            or word == "--token"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--module":
                module = value
            elif word == "--predecessor":
                predecessor = value
            elif word == "--sha":
                digest = value
            elif word == "--fixture":
                fixture = value
            else:
                token = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if predecessor.byte_length() > 0:
        modes += 1
    if fixture.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if predecessor.byte_length() > 0 and (
        digest.byte_length() == 0 or module.byte_length() > 0
    ):
        _usage()
    if fixture.byte_length() > 0 and (
        token.byte_length() == 0
        or migration.byte_length() > 0
        or module.byte_length() > 0
        or predecessor.byte_length() > 0
        or digest.byte_length() > 0
    ):
        _usage()
    try:
        if fixture.byte_length() > 0:
            raw_cut_fixture(Path(fixture).read_text(), token)
            return
        if predecessor.byte_length() > 0:
            raw_cut_digest(Path(predecessor).read_bytes(), digest)
            return
        var text = String("")
        if module.byte_length() > 0:
            text = Path(module).read_text()
        raw_cut_record(Path(migration).read_bytes(), text)
    except error:
        print(String(error), file=stderr)
        exit(1)
