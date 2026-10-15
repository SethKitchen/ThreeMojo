# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Text helpers with the rules of the Python tools they replace.

`String.splitlines` in Mojo 1.1 also splits at a tab, so a tool that reads
source lines must use `split_lines`.
"""


def split_lines(text: String) -> List[String]:
    """Split text at line boundaries, as Python's `str.splitlines` does.

    The boundaries are LF, CR, CR LF, VT, FF, the separators 0x1C to 0x1E,
    NEL, LINE SEPARATOR and PARAGRAPH SEPARATOR.

    Args:
        text: The text.

    Returns:
        The lines, without their boundaries. A final boundary does not make
        an empty last line.
    """
    var bytes = text.as_bytes()
    var lines = List[String]()
    var start = 0
    var i = 0
    while i < len(bytes):
        var width = 0
        var byte = bytes[i]
        if byte == 0x0D:
            width = 2 if i + 1 < len(bytes) and bytes[i + 1] == 0x0A else 1
        elif (
            byte == 0x0A
            or byte == 0x0B
            or byte == 0x0C
            or (byte >= 0x1C and byte <= 0x1E)
        ):
            width = 1
        elif byte == 0xC2 and i + 1 < len(bytes) and bytes[i + 1] == 0x85:
            width = 2
        elif (
            byte == 0xE2
            and i + 2 < len(bytes)
            and bytes[i + 1] == 0x80
            and (bytes[i + 2] == 0xA8 or bytes[i + 2] == 0xA9)
        ):
            width = 3
        if width > 0:
            lines.append(String(unsafe_from_utf8=Span(bytes)[start:i]))
            i += width
            start = i
        else:
            i += 1
    if start < len(bytes):
        lines.append(String(unsafe_from_utf8=Span(bytes)[start:]))
    return lines^
