# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compare two PPM images from the command line.

`examples/capi/run.sh` runs it. From the repository root, the
command is:

    mojo run -I . tools/capi_compare_ppm.mojo A.ppm B.ppm MEAN OUTLIER FRACTION

The work is in `examples/capi/compare_ppm.mojo`. This file holds only `main`, so
that `examples/capi` holds no entry point, and a module there is found from
the repository root only.
"""

from std.sys import argv, exit

from examples.capi.compare_ppm import compare_command


def main() raises:
    """Compare two PPM files from the command line."""
    var arguments = List[String]()
    var given = argv()
    for index in range(1, len(given)):
        arguments.append(String(given[index]))
    exit(compare_command(arguments))
