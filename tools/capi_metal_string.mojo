# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Write a Metal source into a C string header from the command line.

`examples/capi/build.sh` runs it. From the repository root, the
command is:

    mojo run -I . tools/capi_metal_string.mojo IN.metal OUT.h

The work is in `examples/capi/metal_string.mojo`. This file holds only `main`, so
that `examples/capi` holds no entry point, and a module there is found from
the repository root only.
"""

from std.sys import argv, exit

from examples.capi.metal_string import metal_command


def main() raises:
    """Write a Metal source into a C string header."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    exit(metal_command(arguments))
