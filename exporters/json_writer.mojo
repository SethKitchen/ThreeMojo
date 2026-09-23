# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""JSON text, written one value at a time: the other half of
`loaders.json`, and what `exporters.gltf` writes a glTF document with.

`JsonWriter` is a cursor over the text it builds. `begin_object` and
`begin_array` open a container, `end_object` and `end_array` close it,
`key` names the next value in an object, and `string`, `number`,
`integer`, `boolean`, `null` and `raw` write a value. The commas and the
colons are the writer's: a caller says what goes where, and the writer
refuses what JSON has no place for -- a value in an object without a key,
a key outside an object, a close that does not match the open, a second
root value, and a text taken before its root is finished. So a text that
`finish` returns is JSON, whatever the order of the calls was.

**Strings are escaped as RFC 8259 asks.** A quote and a backslash are
escaped, and so is every byte below 32: the five with short forms as
`\\b`, `\\f`, `\\n`, `\\r` and `\\t`, and the rest as `\\u00XX`. Every
other byte is written as it is, so text outside ASCII stays UTF-8, which
JSON allows. `JSON.stringify` does the same.

**Numbers read back to the same `Float32`.** See
`exporters.common.format_float32`. A number that is not finite is
refused, as `JSON.stringify` writes `null` for one and a reader then
finds no number there.
"""

from exporters.common import format_float32
from loaders.json import ARRAY, OBJECT, JsonKind, quote_json


struct JsonWriter(Movable):
    """A JSON text being written, and the containers open in it."""

    var text: String
    # The containers open, the outermost first.
    var _open: List[JsonKind]
    # How many values each open container holds so far.
    var _counts: List[Int]
    # True between a key and its value.
    var _keyed: Bool
    # True once the root value is complete.
    var _done: Bool

    def __init__(out self):
        """Start an empty text."""
        self.text = String()
        self._open = List[JsonKind]()
        self._counts = List[Int]()
        self._keyed = False
        self._done = False

    def _in(self, kind: JsonKind) -> Bool:
        """Return True if the innermost open container is of `kind`."""
        return len(self._open) > 0 and self._open[len(self._open) - 1] == kind

    def _separate(mut self):
        """Write the comma before every entry of a container but its
        first, and count the entry."""
        var last = len(self._counts) - 1
        if self._counts[last] > 0:
            self.text += ","
        self._counts[last] += 1

    def _before_value(mut self) raises:
        """Refuse a value where JSON has no place for one, and write the
        comma before it."""
        if self._done:
            raise Error("JSON writer: a second root value")
        if self._in(OBJECT):
            if not self._keyed:
                raise Error("JSON writer: a value in an object needs a key")
            self._keyed = False
        elif self._in(ARRAY):
            self._separate()

    def _after_value(mut self):
        """Mark the root finished once nothing is open."""
        if len(self._open) == 0:
            self._done = True

    def _write(mut self, value: String) raises:
        """Write one whole value."""
        self._before_value()
        self.text += value
        self._after_value()

    def key(mut self, name: String) raises:
        """Write the key of an object's next value.

        Args:
            name: The key.

        Raises:
            Error: If no object is open, or a key is waiting for its
                value already.
        """
        if not self._in(OBJECT) or self._keyed:
            raise Error("JSON writer: a key needs an open object and a value")
        self._separate()
        self.text += quote_json(name)
        self.text += ":"
        self._keyed = True

    def begin_object(mut self) raises:
        """Open an object.

        Raises:
            Error: If a value has no place here; see the module docstring.
        """
        self._open_container(OBJECT, "{")

    def begin_array(mut self) raises:
        """Open an array.

        Raises:
            Error: If a value has no place here; see the module docstring.
        """
        self._open_container(ARRAY, "[")

    def _open_container(mut self, kind: JsonKind, bracket: String) raises:
        """Open an object or an array."""
        self._before_value()
        self.text += bracket
        self._open.append(kind)
        self._counts.append(0)

    def end_object(mut self) raises:
        """Close the innermost object.

        Raises:
            Error: If the innermost open container is not an object, or a
                key in it has no value.
        """
        self._close(OBJECT, "}")

    def end_array(mut self) raises:
        """Close the innermost array.

        Raises:
            Error: If the innermost open container is not an array.
        """
        self._close(ARRAY, "]")

    def _close(mut self, kind: JsonKind, bracket: String) raises:
        """Close the innermost container, which must be of `kind`."""
        if not self._in(kind) or self._keyed:
            raise Error("JSON writer: a close that does not match its open")
        _ = self._open.pop()
        _ = self._counts.pop()
        self.text += bracket
        self._after_value()

    def string(mut self, value: String) raises:
        """Write a string.

        Args:
            value: The string, escaped here.

        Raises:
            Error: If a value has no place here.
        """
        self._write(quote_json(value))

    def number(mut self, value: Float32) raises:
        """Write a number that reads back to the same `Float32`.

        Args:
            value: The number.

        Raises:
            Error: If it is not finite, or a value has no place here.
        """
        self._write(format_float32(value))

    def integer(mut self, value: Int) raises:
        """Write a whole number.

        Args:
            value: The number.

        Raises:
            Error: If a value has no place here.
        """
        self._write(String(value))

    def boolean(mut self, value: Bool) raises:
        """Write `true` or `false`.

        Args:
            value: The truth.

        Raises:
            Error: If a value has no place here.
        """
        self._write("true" if value else "false")

    def null(mut self) raises:
        """Write `null`.

        Raises:
            Error: If a value has no place here.
        """
        self._write("null")

    def raw(mut self, json: String) raises:
        """Write a value that is JSON already, as it is.

        For a value written by another `JsonWriter` and kept: the text is
        not read again, so it must be one whole JSON value.

        Args:
            json: The value's text.

        Raises:
            Error: If a value has no place here.
        """
        self._write(json)

    def finish(self) raises -> String:
        """Return the text, once its root value is complete.

        Returns:
            The JSON text.

        Raises:
            Error: If no root value was written, or a container is still
                open.
        """
        if not self._done:
            raise Error("JSON writer: the text is not finished")
        return self.text
