# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""UTF-8 bytes for the text readers.

JSON and XML both append one Unicode code point as UTF-8. The caller
has already refused a code point this encoding cannot store. A text
file may also start with the UTF-8 byte order mark, which is not text.

A reader that cuts text at a fixed byte, as three.js cuts at a fixed
character, cuts with `byte_slice`: a cut inside a character moves back to
its first byte, since slicing a `String` there stops the process.
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


def leading_utf8_bom(bytes: Span[UInt8, _]) -> Int:
    """Return how many leading bytes are a UTF-8 byte order mark.

    Args:
        bytes: The start of a file.

    Returns:
        3 when the bytes begin with `EF BB BF`, otherwise 0.
    """
    if (
        len(bytes) >= 3
        and bytes[0] == 0xEF
        and bytes[1] == 0xBB
        and bytes[2] == 0xBF
    ):
        return 3
    return 0


def char_start(text: String, at: Int) -> Int:
    """Return byte `at`, held to the text and moved back to the first byte
    of the character it falls in.

    Args:
        text: The text.
        at: A byte offset.

    Returns:
        An offset from zero through the byte length that starts a
        character or ends the text.
    """
    var bytes = text.as_bytes()
    var cut = min(max(at, 0), len(bytes))
    # A continuation byte is `10xxxxxx`. The first byte of a text never is
    # one, unless the bytes are not UTF-8; zero is a cut either way.
    while cut > 0 and cut < len(bytes) and (bytes[cut] & 0xC0) == 0x80:
        cut -= 1
    return cut


def byte_slice(text: String, start: Int, end: Int) -> String:
    """Return the text from byte `start` to byte `end`, each moved back by
    `char_start`, so a cut never splits a character.

    Args:
        text: The text.
        start: The first byte.
        end: The byte past the last.

    Returns:
        The text between the two cuts, or an empty text when they cross.
    """
    var first = char_start(text, start)
    var last = char_start(text, end)
    if last <= first:
        return String()
    return String(text[byte=first:last])
