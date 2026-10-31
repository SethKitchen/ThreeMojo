# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The values of a calculation package, written for LaTeX.

A drawing set and its calculation report quote the same numbers. A
`TexValues` collects each number once, under a macro name, and writes a
file of `\\newcommand` lines that both documents `\\input`. A changed
input then changes every sheet and page that quotes it.

- `group_thousands`: 12870 becomes `12{,}870`, the way LaTeX keeps the
  comma tight.
- `fixed`: a number with a set count of decimals.
- `feet_inches`: a length as a builder reads it, such as `18'-5"` or
  `9'-0 1/2"`.
"""

from std.math import floor
from std.pathlib import Path
from loaders.js_number import js_to_fixed
from units.si import FOOT64, INCH64, Length64


def _is_macro_name(name: String) -> Bool:
    """Return True if every character is an ASCII letter."""
    if name.byte_length() == 0:
        return False
    # The name is not empty here, so the loop always runs.
    for b in name.as_bytes():  # pragma: no branch
        var c = Int(b)
        if not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122)):
            return False
    return True


def group_thousands(text: String) -> String:
    """Put a LaTeX thousands separator in the whole part of a number.

    Args:
        text: A number as text, such as "-12870.5".

    Returns:
        The text with `{,}` between each group of three digits of the
        whole part, such as "-12{,}870.5".
    """
    var bytes = text.as_bytes()
    var n = len(bytes)
    var start = 0
    if n > 0 and (Int(bytes[0]) == 45 or Int(bytes[0]) == 43):
        start = 1
    var end = start
    while end < n and Int(bytes[end]) >= 48 and Int(bytes[end]) <= 57:
        end += 1
    var out = String()
    for i in range(start):
        out += chr(Int(bytes[i]))
    for i in range(start, end):
        if i > start and (end - i) % 3 == 0:
            out += "{,}"
        out += chr(Int(bytes[i]))
    for i in range(end, n):
        out += chr(Int(bytes[i]))
    return out


def fixed(value: Float64, decimals: Int) raises -> String:
    """Return a number with a set count of decimals.

    Args:
        value: The number.
        decimals: The digits after the point, 0 to 10.

    Returns:
        The text, as JavaScript's toFixed writes it.

    Raises:
        Error: If the digits are out of range or the value is not finite.
    """
    if decimals < 0 or decimals > 10:
        raise Error("A number takes 0 to 10 decimals")
    if not (value > -Float64.MAX and value < Float64.MAX):
        raise Error("A value must be finite")
    return js_to_fixed(value, decimals)


def feet_inches(length: Length64, denominator: Int) raises -> String:
    """Return a length in feet and inches, rounded to a fraction.

    Args:
        length: The length, zero or more.
        denominator: The fraction of an inch to round to: 1, 2, 4, 8 or
            16.

    Returns:
        Text such as `18'-5"`, `9'-0 1/2"` or `0'-3 3/4"`.

    Raises:
        Error: If the length is negative or not finite, or the
            denominator is not a power of two up to 16.
    """
    if not (
        denominator == 1
        or denominator == 2
        or denominator == 4
        or denominator == 8
        or denominator == 16
    ):
        raise Error("A denominator must be 1, 2, 4, 8 or 16")
    var inches = length.to(INCH64)
    if not (inches >= 0 and inches < Float64.MAX):
        raise Error("A length must be zero or more and finite")
    var units = Int(floor(inches * Float64(denominator) + 0.5))
    var per_foot = 12 * denominator
    var feet = units // per_foot
    var rest = units - feet * per_foot
    var whole = rest // denominator
    var numerator = rest - whole * denominator
    var text = String(feet) + "'-" + String(whole)
    if numerator > 0:
        var d = denominator
        while numerator % 2 == 0:
            numerator //= 2
            d //= 2
        text += " " + String(numerator) + "/" + String(d)
    return text + '"'


struct TexValues(Movable):
    """Named values, written as LaTeX macros."""

    var names: List[String]
    var texts: List[String]
    var source: String

    def __init__(out self, var source: String):
        """Start an empty set.

        Args:
            source: What wrote the file, for its first comment line.
        """
        self.names = List[String]()
        self.texts = List[String]()
        self.source = source^

    def add_text(mut self, name: String, text: String) raises:
        """Add a macro that expands to a text.

        Args:
            name: The macro name, ASCII letters only, without a backslash.
            text: The LaTeX text it expands to.

        Raises:
            Error: If the name is not letters or is already used.
        """
        if not _is_macro_name(name):
            raise Error("A macro name must be ASCII letters: " + name)
        for n in self.names:
            if n == name:
                raise Error("A macro name is used twice: " + name)
        self.names.append(name)
        self.texts.append(text)

    def add_number(
        mut self, name: String, value: Float64, decimals: Int
    ) raises:
        """Add a macro that expands to a number, with grouped thousands.

        Args:
            name: The macro name.
            value: The number.
            decimals: The digits after the point.

        Raises:
            Error: If the name is not valid or used, or the number cannot
                be written.
        """
        self.add_text(name, group_thousands(fixed(value, decimals)))

    def add_length(mut self, name: String, length: Length64) raises:
        """Add a macro that expands to a length in feet and inches.

        The inch mark is written as a LaTeX double quote.

        Args:
            name: The macro name.
            length: The length, rounded to 1/2 in.

        Raises:
            Error: If the name is not valid or used, or the length is
                negative.
        """
        self.add_text(name, feet_inches(length, 2))

    def count(self) -> Int:
        """Return the number of macros.

        Returns:
            How many values were added.
        """
        return len(self.names)

    def render(self) -> String:
        """Return the file text.

        Returns:
            A comment line, then one `\\newcommand` per value.
        """
        var out = "% Auto-generated by " + self.source + ". Do not edit.\n"
        for i in range(len(self.names)):
            out += (
                "\\newcommand{\\" + self.names[i] + "}{" + self.texts[i] + "}\n"
            )
        return out

    def write(self, path: String) raises:
        """Write the file.

        Args:
            path: Where to write it.

        Raises:
            Error: If the file cannot be written.
        """
        Path(path).write_text(self.render())


def feet(value: Float64) -> Length64:
    """Return a length given in feet.

    Args:
        value: The number of feet.

    Returns:
        The length.
    """
    return Length64(value, FOOT64)


def inches(value: Float64) -> Length64:
    """Return a length given in inches.

    Args:
        value: The number of inches.

    Returns:
        The length.
    """
    return Length64(value, INCH64)
