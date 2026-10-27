# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Check one operation block or routing text against its pin.

    carla_pin_text PATH

`PATH` is JSON. `kind` is `block`, `digest`, or `same`.
The block kind prints the normalized block. The other kinds print nothing.
"""

from std.pathlib import Path
from std.sys import argv, exit, stderr

from tests._python_tokens import (
    require_operation_block,
    require_same_text,
    require_text_digest,
)
from tools._python_json import PyJson


def _usage():
    """Print the command usage and stop."""
    print("usage: carla_pin_text PATH", file=stderr)
    exit(2)


def main() raises:
    """Check one pinned text.

    Raises:
        Error: The command is invalid, or the pin changed.
    """
    var arguments = argv()
    if len(arguments) != 2:
        _usage()
    var doc = PyJson.parse(Path(arguments[1]).read_text())
    var kind = doc.text(doc.at(doc.root, "kind"))
    if kind != "block" and kind != "digest" and kind != "same":
        _usage()
    try:
        if kind == "block":
            print(
                require_operation_block(
                    doc.text(doc.at(doc.root, "source")),
                    doc.text(doc.at(doc.root, "begin")),
                    doc.text(doc.at(doc.root, "end")),
                    doc.text(doc.at(doc.root, "expected")),
                    doc.text(doc.at(doc.root, "digest")),
                    doc.text(doc.at(doc.root, "name")),
                ),
                end="",
            )
            return
        if kind == "digest":
            require_text_digest(
                doc.text(doc.at(doc.root, "text")),
                doc.text(doc.at(doc.root, "digest")),
                doc.text(doc.at(doc.root, "message")),
            )
            return
        require_same_text(
            doc.text(doc.at(doc.root, "actual")),
            doc.text(doc.at(doc.root, "expected")),
            doc.text(doc.at(doc.root, "message")),
        )
    except error:
        print(String(error), file=stderr)
        exit(1)
