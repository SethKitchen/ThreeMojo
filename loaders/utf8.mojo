# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""UTF-8 bytes for the text readers.

JSON and XML both append one Unicode code point as UTF-8. The caller
has already refused a code point this encoding cannot store.
"""


def append_utf8(mut out: List[UInt8], point: Int):
    """Append one code point as UTF-8.

    Args:
        out: The bytes to extend.
        point: A Unicode code point from 0 through 0x10FFFF.
    """
    if point < 0x80:
        out.append(UInt8(point))
    elif point < 0x800:
        out.append(UInt8(0xC0 | (point >> 6)))
        out.append(UInt8(0x80 | (point & 0x3F)))
    elif point < 0x10000:
        out.append(UInt8(0xE0 | (point >> 12)))
        out.append(UInt8(0x80 | ((point >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (point & 0x3F)))
    else:
        out.append(UInt8(0xF0 | (point >> 18)))
        out.append(UInt8(0x80 | ((point >> 12) & 0x3F)))
        out.append(UInt8(0x80 | ((point >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (point & 0x3F)))
