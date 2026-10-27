# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check an ideal-projection digest.

    carla_ideal_gate --bytes PATH --kind legacy|projected

The program checks the bytes it is given. It does not read the repository
and it does not restore a historical source. The caller does that first.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._sha256 import sha256_hex


comptime _LEGACY_SHA256 = (
    "270a3cde3b012388ee8fcb6a4ecc59d837d1583f6c406f942ff98fdccd9f5733"
)
comptime _PROJECTED_SHA256 = (
    "f0f94e038fd4a783b3ed400ffd32801ca0c3bdc54980e2c408d44f50211b9e06"
)


def ideal_digest(payload: Span[UInt8, _], kind: String) raises:
    """Require one ideal-projection digest.

    Args:
        payload: The UTF-8 bytes of the legacy source or the projected graph.
        kind: `legacy` or `projected`.

    Raises:
        Error: The digest changed.
    """
    if kind == "legacy":
        if sha256_hex(payload) != _LEGACY_SHA256:
            raise Error("historical ideal source changed")
        return
    if kind == "projected":
        if sha256_hex(payload) != _PROJECTED_SHA256:
            raise Error("projected ideal polynomial graph changed")
        return
    raise Error("historical ideal source changed")


def _usage():
    """Print the command usage and stop."""
    print(
        "usage: carla_ideal_gate --bytes PATH --kind legacy|projected",
        file=stderr,
    )
    exit(2)


def main() raises:
    """Check one ideal digest and print nothing on success.

    Raises:
        Error: The command is invalid.
    """
    var payload = String("")
    var kind = String("")
    var arguments = argv()
    var index = 1
    while index < len(arguments):
        var word = arguments[index]
        if word == "--bytes" or word == "--kind":
            if index + 1 >= len(arguments):
                _usage()
            var value = arguments[index + 1]
            if word == "--bytes":
                payload = value
            else:
                kind = value
            index += 2
            continue
        _usage()
    if payload.byte_length() == 0 or (kind != "legacy" and kind != "projected"):
        _usage()
    try:
        ideal_digest(Path(payload).read_bytes(), kind)
    except error:
        print(String(error), file=stderr)
        exit(1)
