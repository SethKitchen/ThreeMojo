# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.
#
# Ported from input2.c and text.h of OWA EPANET 2.3.6. Copyright (c) 2023
# the EPANET contributors. MIT license: see THIRD-PARTY-NOTICES.md.

"""The words of an EPANET input file and the functions that read them.

`matches` compares a keyword with the start of a token, without case, as
EPANET does. So "JUNC" matches "Junctions". `get_tokens` splits a line
into tokens, keeps quoted text as one token, and drops a comment.
"""

from std.math import isfinite

from extensions.epanet.cmath import cstrtod, mul

# Section headings, in the order of the SectionType enumeration.
comptime SECTIONS: List[String] = [
    "[TITLE]",
    "[JUNCTIONS]",
    "[RESERVOIRS]",
    "[TANKS]",
    "[PIPES]",
    "[PUMPS]",
    "[VALVES]",
    "[CONTROLS]",
    "[RULES]",
    "[DEMANDS]",
    "[SOURCES]",
    "[EMITTERS]",
    "[PATTERNS]",
    "[CURVES]",
    "[QUALITY]",
    "[STATUS]",
    "[ROUGHNESS]",
    "[ENERGY]",
    "[REACTIONS]",
    "[MIXING]",
    "[REPORT]",
    "[TIMES]",
    "[OPTIONS]",
    "[COORDINATES]",
    "[VERTICES]",
    "[LABELS]",
    "[BACKDROP]",
    "[TAGS]",
    "[LEAKAGE]",
    "[END]",
]
comptime S_TITLE = 0
comptime S_JUNCTIONS = 1
comptime S_RESERVOIRS = 2
comptime S_TANKS = 3
comptime S_PIPES = 4
comptime S_PUMPS = 5
comptime S_VALVES = 6
comptime S_CONTROLS = 7
comptime S_RULES = 8
comptime S_DEMANDS = 9
comptime S_SOURCES = 10
comptime S_EMITTERS = 11
comptime S_PATTERNS = 12
comptime S_CURVES = 13
comptime S_QUALITY = 14
comptime S_STATUS = 15
comptime S_ROUGHNESS = 16
comptime S_ENERGY = 17
comptime S_REACTIONS = 18
comptime S_MIXING = 19
comptime S_REPORT = 20
comptime S_TIMES = 21
comptime S_OPTIONS = 22
comptime S_COORDS = 23
comptime S_VERTICES = 24
comptime S_LABELS = 25
comptime S_BACKDROP = 26
comptime S_TAGS = 27
comptime S_LEAKAGE = 28
comptime S_END = 29

comptime MIX_WORDS: List[String] = ["MIXED", "2COMP", "FIFO", "LIFO"]
comptime CURVE_WORDS: List[String] = [
    "VOLUME",
    "PUMP",
    "EFFIC",
    "HEADLOSS",
    "GENERIC",
    "VALVE",
]
comptime DEMAND_MODEL_WORDS: List[String] = ["DDA", "PDA"]
comptime BACKFLOW_WORDS: List[String] = ["NO", "YES"]


def matches(text: String, word: String) -> Bool:
    """Return True if `word` matches the start of `text`, without case.

    Leading blanks of `text` are skipped. Each caller gives a keyword
    that is not empty.

    Args:
        text: The text, such as a token of an input line.
        word: The keyword.

    Returns:
        Whether `text` starts with `word`.
    """
    var s = text.as_bytes()
    var w = word.as_bytes()
    var i = 0
    while i < len(s) and s[i] == 32:
        i += 1
    for j in range(len(w)):  # pragma: no branch
        if i >= len(s) or _upper(s[i]) != _upper(w[j]):
            return False
        i += 1
    return True


def _upper(byte: UInt8) -> UInt8:
    """Return the upper case of an ASCII letter, or the byte itself."""
    if byte >= 97 and byte <= 122:
        return byte - 32
    return byte


def findmatch(text: String, words: List[String]) -> Int:
    """Return the index of the first keyword that matches `text`.

    Args:
        text: The text to look up.
        words: The keywords.

    Returns:
        The index into `words`, or -1 if none matches.
    """
    for i in range(len(words)):  # pragma: no branch
        if matches(text, words[i]):
            return i
    return -1


def _is_sep(byte: UInt8) -> Bool:
    """Return True for a token separator: a blank, a tab, LF or CR."""
    return byte == 32 or byte == 9 or byte == 10 or byte == 13


def get_tokens(line: String) -> List[String]:
    """Split a line into tokens, as `gettokens` does.

    Text after a semicolon is a comment. Text between double quotes is
    one token, without the quotes.

    Args:
        line: A line of an input file, with its line feed.

    Returns:
        The tokens.
    """
    var b = line.as_bytes()
    var end = len(b)
    for i in range(len(b)):
        if b[i] == 59:
            end = i
            break
    var tokens = List[String]()
    var s = 0
    var length = end
    while length > 0:
        var m = 0
        while s + m < end and not _is_sep(b[s + m]):
            m += 1
        if m == length:
            tokens.append(String(line[byte=s:end]))
            break
        length -= m + 1
        if m == 0:
            s += 1
        else:
            if b[s] == 34:
                s += 1
                m = 0
                while (
                    s + m < end
                    and b[s + m] != 34
                    and b[s + m] != 10
                    and b[s + m] != 13
                ):
                    m += 1
                length = end - (s + m) - 1
            tokens.append(String(line[byte = s : s + m]))
            s += m + 1
    return tokens^


def get_float(text: String, mut y: Float64) -> Bool:
    """Read a number that fills the whole token, as `getfloat` does.

    The C library reads the number. Hexadecimal numbers, infinities and
    NaN are refused.

    Args:
        text: The token.
        y: Receives the number when the token is one.

    Returns:
        Whether the token is a finite number.
    """
    var used = 0
    var x = cstrtod(text, used)
    if used == 0 or used != text.byte_length():
        return False
    if "x" in text or "X" in text or not isfinite(x):
        return False
    y = x
    return True


def hour(time: String, units: String) -> Float64:
    """Convert a time to hours, as `hour` does.

    Args:
        time: A decimal time or a clock time such as "13:30:10".
        units: Empty, a unit word (SEC, MIN, HOURS, DAYS) or AM or PM.

    Returns:
        The time in hours, or -1 if it cannot be read.
    """
    var y: List[Float64] = [0.0, 0.0, 0.0]
    var n = 0
    for piece in time.split(":"):  # pragma: no branch
        if piece.byte_length() == 0:
            continue
        if n == 3:
            return -1.0
        var x = 0.0
        if not get_float(String(piece), x):
            return -1.0
        y[n] = x
        n += 1
    if n == 1:
        if units.byte_length() == 0:
            return y[0]
        if matches(units, "SEC"):
            return y[0] / 3600.0
        if matches(units, "MIN"):
            return y[0] / 60.0
        if matches(units, "HOU"):
            return y[0]
        if matches(units, "DAY"):
            return mul(y[0], 24.0)
    if n > 1:
        y[0] = y[0] + y[1] / 60.0 + y[2] / 3600.0
    if units.byte_length() == 0:
        return y[0]
    if matches(units, "AM"):
        if y[0] >= 13.0:
            return -1.0
        if y[0] >= 12.0:
            return y[0] - 12.0
        return y[0]
    if matches(units, "PM"):
        if y[0] >= 13.0:
            return -1.0
        if y[0] >= 12.0:
            return y[0]
        return y[0] + 12.0
    return -1.0


def atol(text: String) -> Int:
    """Read the integer at the start of a text, as the C `atol` does.

    Args:
        text: The text.

    Returns:
        The integer, or 0 if the text does not start with one.
    """
    var b = text.as_bytes()
    var i = 0
    while i < len(b) and _is_sep(b[i]):
        i += 1
    var sign = 1
    if i < len(b) and (b[i] == 43 or b[i] == 45):
        if b[i] == 45:
            sign = -1
        i += 1
    var value = 0
    while i < len(b) and b[i] >= 48 and b[i] <= 57:
        value = value * 10 + Int(b[i] - 48)
        i += 1
    return sign * value


def strcmp(a: String, b: String) -> Int:
    """Compare two texts byte by byte, as the C `strcmp` does.

    Args:
        a: The first text.
        b: The second text.

    Returns:
        A negative number, zero or a positive number when `a` comes
        before, equals or comes after `b`.
    """
    var x = a.as_bytes()
    var y = b.as_bytes()
    var n = min(len(x), len(y))
    for i in range(n):
        if x[i] != y[i]:
            return Int(x[i]) - Int(y[i])
    return len(x) - len(y)
