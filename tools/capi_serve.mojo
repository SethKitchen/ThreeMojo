# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Serve a folder on localhost from the command line.

`examples/capi/run.sh` runs it. From the repository root, the
command is:

    mojo run -I . tools/capi_serve.mojo [FOLDER] [PORT]

The work is in `examples/capi/serve.mojo`. This file holds only `main`, so
that `examples/capi` holds no entry point, and a module there is found from
the repository root only.
"""

from std.sys import argv, exit, stderr

from examples.capi.serve import serve_command


def main() raises:
    """Serve a folder from the command line."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    try:
        exit(serve_command(arguments))
    except error:
        print("serve.mojo:", error, file=stderr)
        exit(1)
