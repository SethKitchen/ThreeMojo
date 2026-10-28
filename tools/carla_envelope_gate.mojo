# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check the envelope budget predecessor record.

    carla_envelope_gate --migration PATH
    carla_envelope_gate --source PATH --token HEX
    carla_envelope_gate --span PATH

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
`--span` reads one capture function and refuses a counter name between
the two capacity checks.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import token_names, token_sha256
from tools._sha256 import sha256_hex


comptime _RECORD_SHA256 = (
    "c43aa2bfdfb2a33575745eefb44b2f8ff0714a71a31ad750e8c4c0572fa7f2be"
)


def envelope_record(migration: Span[UInt8, _]) raises:
    """Require the envelope budget predecessor record.

    Args:
        migration: The contract record bytes.

    Raises:
        Error: The digest changed.
    """
    if sha256_hex(migration) != _RECORD_SHA256:
        raise Error("Unreviewed envelope budget predecessor record")


def envelope_token(text: String, expected: String) raises:
    """Require the admission source token digest.

    Args:
        text: The checked source.
        expected: The required token digest.

    Raises:
        Error: The token digest changed.
    """
    if token_sha256(text) != expected:
        raise Error("Reviewed budget admission, routing or arithmetic changed")


comptime _SPAN_START = "    var at = info_index("
"""The first operation after the entry check."""
comptime _SPAN_END = "    if optional_work > max_terms - terms:"
"""The second capacity check."""


def envelope_budget_span(text: String) raises:
    """Refuse a counter name between the two capacity checks.

    Args:
        text: The capture function, already extracted.

    Raises:
        Error: A capacity marker is missing, or `terms` or `max_terms`
            appears between those markers.
    """
    var start = text.find(_SPAN_START)
    if start < 0:
        raise Error("substring not found")
    var end = text.find(_SPAN_END)
    if end < 0:
        raise Error("substring not found")
    var span = String("")
    if end >= start:
        span = String(text[byte=start:end])
    for name in token_names(span):
        if name == "terms" or name == "max_terms":
            raise Error("Intervening span can access budget parameters")


def _usage():
    """Print the command usage and stop."""
    print(
        (
            "usage: carla_envelope_gate --migration PATH"
            " | --source PATH --token HEX | --span PATH"
        ),
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check the envelope record and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var migration = String("")
    var source = String("")
    var token = String("")
    var span = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if (
            word == "--migration"
            or word == "--source"
            or word == "--token"
            or word == "--span"
        ):
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--migration":
                migration = value
            elif word == "--source":
                source = value
            elif word == "--span":
                span = value
            else:
                token = value
            index += 2
            continue
        _usage()
    var modes = 0
    if migration.byte_length() > 0:
        modes += 1
    if source.byte_length() > 0:
        modes += 1
    if span.byte_length() > 0:
        modes += 1
    if modes != 1:
        _usage()
    if source.byte_length() > 0 and token.byte_length() == 0:
        _usage()
    if migration.byte_length() > 0 and token.byte_length() > 0:
        _usage()
    if span.byte_length() > 0 and token.byte_length() > 0:
        _usage()
    try:
        if source.byte_length() > 0:
            envelope_token(Path(source).read_text(), token)
            return
        if span.byte_length() > 0:
            envelope_budget_span(Path(span).read_text())
            return
        envelope_record(Path(migration).read_bytes())
    except error:
        print(String(error), file=stderr)
        exit(1)
