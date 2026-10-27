# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Write bytes from hexadecimal text.

    carla_payload_bytes INPUT OUTPUT

`INPUT` is hexadecimal text. `OUTPUT` receives the decoded bytes.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tools._payload_bytes import from_hex


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_payload_bytes INPUT OUTPUT", file=stderr)
    exit(2)


def main() raises:
    """Decode one hexadecimal payload into a byte file.

    Raises:
        Error: The command is invalid, or the text is not hexadecimal.
    """
    var arguments = argv()
    if len(arguments) != 3:
        _usage()
    try:
        var data = Path(arguments[1]).read_bytes()
        var payload = from_hex(String(unsafe_from_utf8=data))
        Path(arguments[2]).write_bytes(Span(payload))
    except error:
        print(String(error), file=stderr)
        exit(1)
