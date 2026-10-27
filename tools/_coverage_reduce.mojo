# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Reduce one captured standard-error stream.

The lines keep their original boundaries, as `splitlines(keepends=True)`
does, and the reducer keeps each distinct probe once.
"""

from tools.coverage_io import Reducer


def _boundary(bytes: Span[UInt8, _], index: Int) -> Int:
    """Return the width of a Python line boundary at `index`.

    Args:
        bytes: The captured bytes.
        index: The first byte to inspect.

    Returns:
        The boundary width, or 0 when `index` is not a boundary.
    """
    var byte = bytes[index]
    if byte == 0x0D:
        if index + 1 < len(bytes) and bytes[index + 1] == 0x0A:
            return 2
        return 1
    if (
        byte == 0x0A
        or byte == 0x0B
        or byte == 0x0C
        or (byte >= 0x1C and byte <= 0x1E)
    ):
        return 1
    if byte == 0xC2 and index + 1 < len(bytes) and bytes[index + 1] == 0x85:
        return 2
    if (
        byte == 0xE2
        and index + 2 < len(bytes)
        and bytes[index + 1] == 0x80
        and (bytes[index + 2] == 0xA8 or bytes[index + 2] == 0xA9)
    ):
        return 3
    return 0


def reduce_capture(raw: String) raises -> String:
    """Reduce `raw` the way a diagnostic capture reduces standard error.

    Args:
        raw: The captured standard error.

    Returns:
        The reduced text.

    Raises:
        Error: A probe record is malformed.
    """
    var reducer = Reducer()
    var bytes = raw.as_bytes()
    var start = 0
    var index = 0
    while index < len(bytes):
        var width = _boundary(bytes, index)
        if width > 0:
            reducer.feed(
                String(unsafe_from_utf8=Span(bytes)[start : index + width])
            )
            index += width
            start = index
        else:
            index += 1
    if start < len(bytes):
        reducer.feed(String(unsafe_from_utf8=Span(bytes)[start:]))
    return reducer.output
