# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Text as JavaScript holds it: UTF-16 code units, for the loaders that
must find, cut and trim text where three.js does.

A JavaScript string is a list of 16-bit code units. A code point past the
first plane is two units, a surrogate pair. `js_units` makes that list
from a Mojo string, and `js_string` makes a string from part of it. An
index into the list is an index JavaScript's `slice`, `indexOf` and
`lastIndex` count in.

`is_js_space` is the white space that JavaScript's `\\s` and `trim` match:
the ASCII spaces, the line terminators, and the Unicode spaces.
"""


def is_js_space(unit: Int) -> Bool:
    """Return True for a code unit JavaScript's `\\s` and `trim` match.

    Args:
        unit: The UTF-16 code unit.

    Returns:
        Whether it is white space or a line terminator.
    """
    if unit >= 9 and unit <= 13:
        return True
    if unit >= 0x2000 and unit <= 0x200A:
        return True
    var spaces: List[Int] = [
        32,
        0xA0,
        0x1680,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
        0xFEFF,
    ]
    return unit in spaces


def js_units(text: String) -> List[Int]:
    """Return a text's UTF-16 code units, as JavaScript holds a string.

    Args:
        text: The text.

    Returns:
        The code units.
    """
    var out = List[Int]()
    for c in text.codepoints():
        var v = Int(c.to_u32())
        if v > 0xFFFF:
            v -= 0x10000
            out.append(0xD800 + (v >> 10))
            out.append(0xDC00 + (v & 0x3FF))
        else:
            out.append(v)
    return out^


def js_string(units: List[Int], start: Int, end: Int) -> String:
    """Return some code units as a string.

    Args:
        units: The code units, whole code points each.
        start: The first.
        end: One past the last.

    Returns:
        The text.
    """
    var out = String()
    var k = start
    while k < end:
        var v = units[k]
        k += 1
        # A high surrogate: the units come from whole code points, so its
        # low one follows.
        if v >= 0xD800 and v < 0xDC00:
            v = 0x10000 + ((v - 0xD800) << 10) + (units[k] - 0xDC00)
            k += 1
        out += chr(v)
    return out^


def js_part(units: List[Int], start: Int, end: Int) -> List[Int]:
    """Return a copy of some code units.

    Args:
        units: The code units.
        start: The first.
        end: One past the last.

    Returns:
        The copy.
    """
    var out = List[Int](capacity=max(end - start, 0))
    for k in range(start, end):
        out.append(units[k])
    return out^


def js_trim(units: List[Int]) -> List[Int]:
    """Return JavaScript's `trim`.

    Args:
        units: The code units.

    Returns:
        The code units less white space at both ends.
    """
    var start = 0
    var end = len(units)
    while start < end and is_js_space(units[start]):
        start += 1
    while end > start and is_js_space(units[end - 1]):
        end -= 1
    return js_part(units, start, end)
