# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Numbers that the exporters write so that they read back exactly.

**A JSON number is written so it reads back to the same `Float32`.**
`format_float32` writes the shortest text that does so, which is what
`String(Float32)` aims for. It misses by one unit in the last place for
about one number in two hundred, so `format_float32` reads its own answer
back and, when it is wrong, writes the number's exact `Float64` form
instead, which always reads back. A number that is not finite is refused:
no text format here can hold one, and every loader here refuses one.

**OBJ, STL and PLY write a number as three.js does.** three.js holds a
vertex value as a double and writes JavaScript's `String` of it:
`0.10000000149011612` for the `Float32` nearest a tenth.
`format_js_float32` writes the exact `Float64` of a `Float32` that way,
so a value passed through as it is has the same text. A value that
three.js works out through a matrix in doubles, and this port in
`Float32`s, has the same text only when both are exact.
"""

from loaders.js_number import js_number_text
from std.math import isfinite


def require_finite_written_number(value: Float32) raises:
    """Refuse a number that cannot be written.

    Nothing. The call returns when the number is finite.

    Args:
        value: The number.

    Raises:
        Error: If the number is not finite.
    """
    if not isfinite(Float64(value)):
        raise Error("A number to write must be finite: " + String(value))


def format_float32(value: Float32) raises -> String:
    """Return the text of a number that reads back to the same `Float32`.

    Args:
        value: The number.

    Returns:
        The shortest text when it reads back exactly, else the number's
        exact `Float64` text. Both are JSON numbers, and both read as
        numbers in OBJ, STL and PLY.

    Raises:
        Error: If the number is not finite.
    """
    require_finite_written_number(value)
    var short = String(value)
    if Float32(Float64(short)) == value:
        return short
    # `Float64(value)` is exact, and its shortest text reads back to it.
    return String(Float64(value))


def format_js_float32(value: Float32) raises -> String:
    """Return the text three.js writes for a `Float32` it holds as a
    double: JavaScript's `String` of the number's exact `Float64`.

    Args:
        value: The number.

    Returns:
        `1` for one, `0.5` for a half, and `0.10000000149011612` for the
        `Float32` nearest a tenth, as three.js writes each. It reads back
        to the same `Float32`.

    Raises:
        Error: If the number is not finite.
    """
    require_finite_written_number(value)
    return js_number_text(Float64(value))
