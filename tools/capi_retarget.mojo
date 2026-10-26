# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Retarget one LLVM IR file to wasm32 from the command line.

`examples/capi/build.sh` runs it. From the repository root, the
command is:

    mojo run -I . tools/capi_retarget.mojo CLANG IN.ll OUT.ll

The work is in `examples/capi/retarget.mojo`. This file holds only `main`, so
that `examples/capi` holds no entry point, and a module there is found from
the repository root only.
"""

from std.sys import argv, exit

from examples.capi.retarget import retarget_command


def main() raises:
    """Retarget one LLVM IR file from the command line."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    exit(retarget_command(arguments))
