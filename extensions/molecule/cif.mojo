# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Read the first data block of a CIF or mmCIF file into tables.

The tokens follow CIF 1.1. Space, tab and the line end separate them. A
`#` starts a comment that runs to the end of the line. A value in single
or double quotes ends at a matching quote that is followed by a blank or
the end of the text, so `'O'Brien'` is one value. A line that starts with
`;` opens a text field, and the next line that starts with `;` closes it.

A data block starts with `data_NAME`. A name such as `_atom_site.id`
takes the next value. `loop_` and the names after it start a table, and
the values after them fill its rows. A name is not case sensitive: the
block stores it in lower case. `.` and `?` are kept as they are.
`is_null` tells them apart from data.
"""

from std.pathlib import Path


@fieldwise_init
struct CifToken(Copyable, Movable):
    """One name or value of a CIF file, and its line."""

    var text: String
    """The text, without quotes or the semicolons of a text field."""
    var quoted: Bool
    """Whether the text was in quotes or a text field."""
    var line: Int
    """The line the token starts on, from one."""


def _blank(byte: UInt8) -> Bool:
    """Return whether a byte separates tokens."""
    return byte == 32 or byte == 9 or byte == 10 or byte == 13


def _text(bytes: Span[UInt8, _], start: Int, end: Int) -> String:
    """Return the text of a byte range."""
    return String(from_utf8_lossy=bytes[start:end])


def cif_tokens(text: String) raises -> List[CifToken]:
    """Return the tokens of CIF text.

    Args:
        text: The text of the file.

    Returns:
        The names and values, in order.

    Raises:
        Error: If a quoted value or a text field has no end.
    """
    var bytes = text.as_bytes()
    var n = len(bytes)
    var out = List[CifToken]()
    var at = 0
    var line = 1
    var line_start = True
    while at < n:
        var ch = bytes[at]
        if ch == 10:
            line += 1
            line_start = True
            at += 1
            continue
        if _blank(ch):
            if ch != 13:
                line_start = False
            at += 1
            continue
        if ch == 59 and line_start:
            at = _text_field(bytes, at, line, out)
            line = out[len(out) - 1].line + _lines(out[len(out) - 1].text) + 1
            line_start = False
            continue
        line_start = False
        if ch == 35:
            while at < n and bytes[at] != 10:
                at += 1
            continue
        if ch == 39 or ch == 34:
            var end = at + 1
            while end < n:
                if bytes[end] == 10:
                    end = n
                elif bytes[end] == ch and (
                    end + 1 == n or _blank(bytes[end + 1])
                ):
                    break
                else:
                    end += 1
            if end >= n:
                raise Error(
                    String("Line ", line, ": a quoted value has no end")
                )
            out.append(CifToken(_text(bytes, at + 1, end), True, line))
            at = end + 1
            continue
        var end = at
        while end < n and not _blank(bytes[end]):
            end += 1
        out.append(CifToken(_text(bytes, at, end), False, line))
        at = end
    return out^


def _lines(text: String) -> Int:
    """Return how many line ends a text holds."""
    var count = 0
    for byte in text.as_bytes():
        if byte == 10:
            count += 1
    return count


def _text_field(
    bytes: Span[UInt8, _], at: Int, line: Int, mut out: List[CifToken]
) raises -> Int:
    """Append the text field that starts at `at`, and return the place after."""
    var n = len(bytes)
    var end = at + 1
    while end + 1 < n and not (bytes[end] == 10 and bytes[end + 1] == 59):
        end += 1
    if end + 1 >= n:
        raise Error(String("Line ", line, ": a text field has no end"))
    var stop = end
    if stop > at + 1 and bytes[stop - 1] == 13:
        stop -= 1
    out.append(CifToken(_text(bytes, at + 1, stop), True, line))
    return end + 2


def is_null(value: String) -> Bool:
    """Return whether a value is CIF's `.` (does not apply) or `?` (unknown).

    Args:
        value: The value.

    Returns:
        Whether it is `.` or `?`.
    """
    return value == "." or value == "?"


struct CifTable(Copyable, Movable):
    """A loop, or one name and its value as a table of one row."""

    var tags: List[String]
    """The names of the columns, in lower case."""
    var values: List[String]
    """The values, row by row."""

    def __init__(out self, var tags: List[String], var values: List[String]):
        """Create a table.

        Args:
            tags: The names of the columns.
            values: The values, row by row. A whole number of rows.
        """
        self.tags = tags^
        self.values = values^

    def rows(self) -> Int:
        """Return the number of rows.

        Returns:
            The value count divided by the column count.
        """
        return len(self.values) // len(self.tags)


struct CifBlock(Copyable, Movable):
    """The tables of one data block."""

    var name: String
    """The block's name, after `data_`."""
    var tables: List[CifTable]
    """The tables, in the order of the file."""

    def __init__(out self, name: String, var tables: List[CifTable]):
        """Create a block.

        Args:
            name: The block's name.
            tables: Its tables.
        """
        self.name = name
        self.tables = tables^

    def find(self, tag: String) -> Tuple[Int, Int]:
        """Return the table and the column of a name.

        Args:
            tag: The name, in any case, such as `_atom_site.Cartn_x`.

        Returns:
            The table index and the column index, or `(-1, -1)` when the
            block does not have the name.
        """
        var lower = tag.lower()
        for t in range(len(self.tables)):
            ref table = self.tables[t]
            for c in range(len(table.tags)):  # pragma: no branch
                if table.tags[c] == lower:
                    return (t, c)
        return (-1, -1)

    def has(self, tag: String) -> Bool:
        """Return whether the block has a name.

        Args:
            tag: The name, in any case.

        Returns:
            Whether a table has the name.
        """
        return self.find(tag)[0] >= 0

    def column(self, tag: String) raises -> List[String]:
        """Return the values of one name, one for each row of its table.

        Args:
            tag: The name, in any case.

        Returns:
            The values.

        Raises:
            Error: If the block does not have the name.
        """
        var place = self.find(tag)
        if place[0] < 0:
            raise Error("The CIF block has no " + tag)
        ref table = self.tables[place[0]]
        var width = len(table.tags)
        var out = List[String]()
        for row in range(table.rows()):
            out.append(table.values[row * width + place[1]])
        return out^

    def column_or(
        self, tag: String, fallback: String, rows: Int
    ) raises -> List[String]:
        """Return the values of a name, or `rows` copies of a fallback.

        Args:
            tag: The name, in any case.
            fallback: The value to use when the block does not have it.
            rows: The number of rows that the column must have.

        Returns:
            The values.

        Raises:
            Error: If the name's table has a different number of rows.
        """
        if not self.has(tag):
            return List[String](length=rows, fill=fallback)
        var values = self.column(tag)
        if len(values) != rows:
            raise Error("The CIF column " + tag + " has the wrong row count")
        return values^


def _starts_item(token: CifToken) -> Bool:
    """Return whether a token is a name, `loop_` or a data block."""
    if token.quoted:
        return False
    var lower = token.text.lower()
    return (
        lower.startswith("_") or lower == "loop_" or lower.startswith("data_")
    )


def parse_cif(text: String) raises -> CifBlock:
    """Return the first data block of CIF text.

    Args:
        text: The text of the file.

    Returns:
        The block. Later blocks are ignored.

    Raises:
        Error: If the text has no data block, a token is in the wrong
            place, a loop has no names or does not fill its rows, a name
            has no value, or a quoted value or text field has no end.
    """
    var tokens = cif_tokens(text)
    var k = 0
    while k < len(tokens) and not (
        _starts_item(tokens[k]) and tokens[k].text.lower().startswith("data_")
    ):
        k += 1
    if k == len(tokens):
        raise Error("A CIF file needs a data block")
    var name = String(tokens[k].text[byte=5:])
    k += 1
    var tables = List[CifTable]()
    while k < len(tokens):
        ref token = tokens[k]
        if not _starts_item(token):
            raise Error(
                String(
                    "Line ", token.line, ": '", token.text, "' is not a name"
                )
            )
        var lower = token.text.lower()
        if lower.startswith("data_"):
            break
        if lower == "loop_":
            k += 1
            var tags = List[String]()
            while (
                k < len(tokens)
                and _starts_item(tokens[k])
                and tokens[k].text.startswith("_")
            ):
                tags.append(tokens[k].text.lower())
                k += 1
            if len(tags) == 0:
                raise Error(String("Line ", token.line, ": a loop has no name"))
            var values = List[String]()
            while k < len(tokens) and not _starts_item(tokens[k]):
                values.append(tokens[k].text)
                k += 1
            if len(values) % len(tags) != 0:
                raise Error(
                    String("Line ", token.line, ": a loop's values do not")
                    + " fill its rows"
                )
            tables.append(CifTable(tags^, values^))
            continue
        if k + 1 >= len(tokens) or _starts_item(tokens[k + 1]):
            raise Error(
                String("Line ", token.line, ": ", token.text, " has no value")
            )
        var tags: List[String] = [lower]
        var values: List[String] = [tokens[k + 1].text]
        tables.append(CifTable(tags^, values^))
        k += 2
    return CifBlock(name, tables^)


def read_cif(path: String) raises -> CifBlock:
    """Return the first data block of a CIF file.

    Args:
        path: The file.

    Returns:
        The block.

    Raises:
        Error: If the file cannot be read, or `parse_cif` refuses it.
    """
    return parse_cif(Path(path).read_text())
