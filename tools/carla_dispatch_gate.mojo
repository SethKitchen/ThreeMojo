# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the curve support and dispatch migration record.

    carla_dispatch_gate --migration PATH
    carla_dispatch_gate --bytes PATH --sha HEX --label TEXT
    carla_dispatch_gate --tokens DIR

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_sha256
from tools._python_json import MISSING, PY_DICT, PY_LIST, PyJson, py_equal
from tools._sha256 import sha256_hex


comptime _MIGRATION_SHA256 = (
    "1a6d7794bf0869a1e717685e556d8400e075ab97917ce8d855da6bd61c3ee19f"
)


def _fail(message: String) raises:
    """Raise one support/dispatch failure.

    Args:
        message: The reason, without the prefix.

    Raises:
        Error: Always.
    """
    raise Error("curve support/dispatch contract: " + message)


def _source_name(index: Int) -> String:
    """Return one reviewed source path.

    Args:
        index: The path position, 0 or 1.

    Returns:
        The repository path.
    """
    if index == 0:
        return "extensions/carla/curve_minimizer_support.mojo"
    return "extensions/carla/curve_sample_dispatch.mojo"


def _sources_match(doc: PyJson, node: Int) -> Bool:
    """Return whether the source keys are the reviewed set.

    Args:
        doc: The record.
        node: The sources object.

    Returns:
        True when the keys are exactly the two reviewed paths.
    """
    if node == MISSING or doc.kind(node) != PY_DICT or doc.length(node) != 2:
        return False
    var index = 0
    while index < 2:
        if doc.get(node, _source_name(index)) == MISSING:
            return False
        index += 1
    return True


def dispatch_record(migration: Span[UInt8, _]) raises:
    """Require the support and dispatch migration.

    Args:
        migration: The successor record bytes.

    Raises:
        Error: The digest, the schema, or the source set changed.
    """
    if sha256_hex(migration) != _MIGRATION_SHA256:
        _fail("unreviewed migration record")
    var doc = PyJson.parse(String(from_utf8_lossy=migration))
    var schema = doc.get(doc.root, "schema")
    var one = PyJson.parse("1")
    if schema == MISSING or not py_equal(doc, schema, one, one.root):
        _fail("wrong successor schema or source set")
    if not _sources_match(doc, doc.get(doc.root, "sources")):
        _fail("wrong successor schema or source set")


def dispatch_pin(
    payload: Span[UInt8, _], expected: String, label: String
) raises:
    """Require one historical pin digest.

    Args:
        payload: The pin file bytes.
        expected: The required SHA-256 hex digest.
        label: The repository path, used in the failure text.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(payload) != expected:
        _fail("standalone historical pin input changed: " + label)


def dispatch_tokens(directory: String) raises:
    """Require each text to have its recorded token digest.

    Args:
        directory: A directory with `labels.json` and `N.text` files.

    Raises:
        Error: A token digest changed, or the directory cannot be read.
    """
    var doc = PyJson.parse(Path(directory + "/labels.json").read_text())
    if doc.kind(doc.root) != PY_LIST:
        _fail("complete successor changed")
    var index = 0
    var count = doc.length(doc.root)
    while index < count:
        var row = doc.item(doc.root, index)
        var label = doc.text(doc.at(row, "label"))
        var expected = doc.text(doc.at(row, "token"))
        var text = Path(directory + "/" + String(index) + ".text").read_text()
        if token_sha256(text) != expected:
            _fail(label)
        index += 1


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_dispatch_gate --migration PATH"
            " | --bytes PATH --sha HEX --label TEXT | --tokens DIR"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the support and dispatch record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var payload = String("")
    var digest = String("")
    var label = String("")
    var tokens = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--bytes"
            or word == "--sha"
            or word == "--label"
            or word == "--tokens"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--bytes":
                payload = value
            elif word == "--sha":
                digest = value
            elif word == "--label":
                label = value
            else:
                tokens = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if payload.byte_length() > 0:
        modes += 1
    if tokens.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if payload.byte_length() > 0 and (
        digest.byte_length() == 0 or label.byte_length() == 0
    ):
        _usage()
    try:
        if tokens.byte_length() > 0:
            dispatch_tokens(tokens)
            return
        if migration.byte_length() > 0:
            dispatch_record(Path(migration).read_bytes())
        else:
            dispatch_pin(Path(payload).read_bytes(), digest, label)
    except error:
        print(String(error), file=stderr)
        exit(1)
