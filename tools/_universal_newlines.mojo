# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md

"""Translate universal newlines the way Python reads text.

`\\n`, `\\r\\n`, and a lone `\\r` all become `\\n`. Other bytes stay in
place.
"""


def universal_newlines(text: String) -> String:
    """Return `text` with universal newlines translated to `\\n`.

    Args:
        text: A decoded string. Newline bytes are still `\\n` or `\\r`.

    Returns:
        The same text, with each newline sequence written as `\\n`.
    """
    var raw = text.as_bytes()
    var out = List[UInt8]()
    var index = 0
    var count = len(raw)
    while index < count:
        var byte = raw[index]
        if byte == 13:
            if index + 1 < count and raw[index + 1] == 10:
                index += 1
            out.append(10)
        else:
            out.append(byte)
        index += 1
    return String(unsafe_from_utf8=Span(out))
