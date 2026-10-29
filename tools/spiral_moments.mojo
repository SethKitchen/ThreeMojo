# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Regenerate or check the stored spiral-moment table.

    mojo run -I . tools/spiral_moments.mojo [--check]

The table is `extensions/carla/spiral_moment_table_data.mojo`. Its words
are exact binary64 brackets of the moments of the stored Gauss-Legendre
nodes and weights and the stored trig coefficients. `--check` exits with
status 1 when the table differs from the derivation.
"""

from std.pathlib import Path
from std.sys import argv, exit

from tools._spiral_moment_derive import (
    derive_endpoints,
    stored_coefficient_words,
)
from tools._spiral_moment_table_text import canonical_table

comptime GEOMETRY = "extensions/carla/geometry.mojo"
comptime TRIG = "extensions/carla/curve_trig.mojo"
comptime TABLE = "extensions/carla/spiral_moment_table_data.mojo"


def derived_table() raises -> String:
    """Return the table source derived from the live constants.

    Returns:
        The canonical generated source of the table.

    Raises:
        Error: A live constant or an endpoint is refused.
    """
    var geometry = Path(GEOMETRY).read_text()
    var trig = Path(TRIG).read_text()
    return canonical_table(
        derive_endpoints(
            stored_coefficient_words(geometry, "_GL_NODES", 5),
            stored_coefficient_words(geometry, "_GL_WEIGHTS", 5),
            stored_coefficient_words(trig, "_COS_COEFFICIENTS", 11),
            stored_coefficient_words(trig, "_SIN_COEFFICIENTS", 11),
        )
    )


def main() raises:
    """Write the table, or check it with `--check`.

    Raises:
        Error: If the derivation fails or the command line is not valid.
    """
    var args = argv()
    var text = derived_table()
    if len(args) == 2 and args[1] == "--check":
        if Path(TABLE).read_text() != text:
            print(TABLE + " differs from the derivation.")
            exit(1)
        return
    if len(args) != 1:
        raise Error("usage: spiral_moments [--check]")
    Path(TABLE).write_text(text)
