# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A strict decimal read for a geometry coordinate, and the line an error names.

OBJ, MTL, STL and a cube LUT read a field with Mojo's `Float64`, then keep
it only when it is finite as the `Float32` a geometry stores. A text that
is not a number names the parser's reason. A number that overflows a
`Float32` is refused before it can become an infinity in a bound or a
normal. `file_line` builds the `KIND line N: ` prefix a loader error uses.
"""

from std.math import isfinite


def read_finite_float32(
    field: String, prefix: String, finite: String
) raises -> Float32:
    """Return a field as a finite `Float32`.

    Args:
        field: The text.
        prefix: The prefix of both errors, including its trailing space.
        finite: The words before the field when the number is not finite,
            such as `a coordinate must be a finite number`.

    Returns:
        The number.

    Raises:
        Error: If the field is not a number, or is not finite as a
            `Float32`.
    """
    var wide: Float64
    try:
        wide = Float64(field)
    except reason:
        raise Error(
            prefix + "not a number: " + field + " (" + String(reason) + ")"
        )
    var narrow = Float32(wide)
    if not isfinite(narrow):
        raise Error(prefix + finite + ": " + field)
    return narrow


def file_line(kind: String, line: Int) -> String:
    """Return the prefix an error names a line with.

    Error: Never.

    Args:
        kind: The file kind, such as `OBJ` or `PLY header`.
        line: The line number.

    Returns:
        `kind`, then ` line `, then the number, then `: `.

    """
    return kind + " line " + String(line) + ": "
