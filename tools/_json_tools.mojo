# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""JSON reading and writing with the rules of the Python tools they replace.

The ported tools read JSON with `loaders.json`. These helpers give the
Python meanings that the old tools relied on:

- `get` is `dict.get`: a missing key, or a value that is not an object,
  gives `MISSING`, which acts as `None`.
- `index` is `dict[key]`: a missing key raises an error with Python's
  `KeyError` text.
- `truthy` and `equal` follow Python truth and `==` on the decoded values.

`JsonWriter` writes text as `json.dumps(value, indent=2)` does, with every
character outside printable ASCII escaped.
"""

from std.math import isinf, isnan

from tools._python_float import python_repr

from loaders.json import (
    ARRAY,
    BOOLEAN,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    JsonDocument,
)

comptime MISSING = -1
"""The node index of an absent value. It acts as Python's `None`."""
comptime _HEX = "0123456789abcdef"
comptime _INDENT = "  "


def get(document: JsonDocument, node: Int, key: String) raises -> Int:
    """Return a member as `dict.get` does.

    Args:
        document: The parsed document.
        node: An object node, or any other node or `MISSING`.
        key: The member name.

    Returns:
        The member's node, or `MISSING` when `node` is not an object or has
        no such member.

    Raises:
        Error: If `node` is not a node of `document`.
    """
    if node == MISSING or document.kind(node) != OBJECT:
        return MISSING
    if not document.has(node, key):
        return MISSING
    return document.get(node, key)


def index(document: JsonDocument, node: Int, key: String) raises -> Int:
    """Return a member as `dict[key]` does.

    Args:
        document: The parsed document.
        node: An object node.
        key: The member name.

    Returns:
        The member's node.

    Raises:
        Error: `'key'`, as Python's `KeyError` prints, when the member is
            absent or `node` is not an object.
    """
    var found = get(document, node, key)
    if found == MISSING:
        raise Error("'" + key + "'")
    return found


def is_none(document: JsonDocument, node: Int) raises -> Bool:
    """Return whether a value is `None`: absent or JSON `null`.

    Args:
        document: The parsed document.
        node: A node or `MISSING`.

    Returns:
        True for `MISSING` and `null`.
    """
    return node == MISSING or document.kind(node) == NULL


def truthy(document: JsonDocument, node: Int) raises -> Bool:
    """Return the Python truth value of a decoded value.

    Args:
        document: The parsed document.
        node: A node or `MISSING`.

    Returns:
        False for `None`, `false`, zero, and empty strings, arrays and
        objects; True otherwise.
    """
    if is_none(document, node):
        return False
    var kind = document.kind(node)
    if kind == OBJECT or kind == ARRAY:
        return document.length(node) > 0
    if kind == STRING:
        return document.string(node).byte_length() > 0
    if kind == NUMBER:
        return document.number(node) != 0
    return document.boolean(node)


def _numeric(document: JsonDocument, node: Int) raises -> Float64:
    """Return a number or a Boolean as Python compares it."""
    if document.kind(node) == BOOLEAN:
        return 1.0 if document.boolean(node) else 0.0
    return document.number(node)


def equal(
    left: JsonDocument, a: Int, right: JsonDocument, b: Int
) raises -> Bool:
    """Return whether two decoded values are equal under Python's `==`.

    Objects compare by their member sets, arrays by position. Numbers and
    Booleans compare by value, as `True == 1` does in Python.

    Args:
        left: The first document.
        a: A node of `left`, or `MISSING`.
        right: The second document.
        b: A node of `right`, or `MISSING`.

    Returns:
        True when the values are equal.
    """
    if is_none(left, a) or is_none(right, b):
        return is_none(left, a) and is_none(right, b)
    var ka = left.kind(a)
    var kb = right.kind(b)
    if (ka == NUMBER or ka == BOOLEAN) and (kb == NUMBER or kb == BOOLEAN):
        return _numeric(left, a) == _numeric(right, b)
    if ka != kb:
        return False
    if ka == STRING:
        return left.string(a) == right.string(b)
    var count = left.length(a)
    if count != right.length(b):
        return False
    if ka == ARRAY:
        for i in range(count):
            if not equal(left, left.at(a, i), right, right.at(b, i)):
                return False
        return True
    for i in range(count):
        var key = left.key(a, i)
        if not right.has(b, key):
            return False
        if not equal(left, left.get(a, key), right, right.get(b, key)):
            return False
    return True


def equals_text(document: JsonDocument, node: Int, text: String) raises -> Bool:
    """Return whether a value is the string `text`.

    Args:
        document: The parsed document.
        node: A node or `MISSING`.
        text: The expected string.

    Returns:
        True for a string node with that text.
    """
    return (
        node != MISSING
        and document.kind(node) == STRING
        and document.string(node) == text
    )


def equals_texts(
    document: JsonDocument, node: Int, texts: List[String]
) raises -> Bool:
    """Return whether a value is an array of exactly these strings.

    Args:
        document: The parsed document.
        node: A node or `MISSING`.
        texts: The expected strings, in order.

    Returns:
        True for an array of equal strings in the same order.
    """
    if node == MISSING or document.kind(node) != ARRAY:
        return False
    if document.length(node) != len(texts):
        return False
    for i in range(len(texts)):
        if not equals_text(document, document.at(node, i), texts[i]):
            return False
    return True


def keys(document: JsonDocument, node: Int) raises -> List[String]:
    """Return an object's member names in file order.

    Args:
        document: The parsed document.
        node: A node or `MISSING`.

    Returns:
        The names, or an empty list when `node` is not an object.
    """
    var names = List[String]()
    if node == MISSING or document.kind(node) != OBJECT:
        return names^
    for i in range(document.length(node)):
        names.append(document.key(node, i))
    return names^


def python_text(document: JsonDocument, node: Int) raises -> String:
    """Return `str()` of a decoded scalar, as the Python tools printed it.

    Args:
        document: The parsed document.
        node: A node or `MISSING`.

    Returns:
        A string's text, an integral number without a fraction, `True`,
        `False` or `None`. Arrays and objects give their JSON text.
    """
    if is_none(document, node):
        return "None"
    var kind = document.kind(node)
    if kind == STRING:
        return document.string(node)
    if kind == BOOLEAN:
        return "True" if document.boolean(node) else "False"
    if kind == NUMBER:
        var value = document.number(node)
        if value == Float64(Int(value)):
            return String(Int(value))
        return String(value)
    var writer = JsonWriter()
    writer.node(document, node)
    return writer.text()


def quote_ascii(text: String) -> String:
    """Return a JSON string as Python's `json.dumps` writes it by default.

    Every character outside printable ASCII is a `\\u` escape, with a
    surrogate pair above U+FFFF.

    Args:
        text: The string.

    Returns:
        The quoted string.
    """
    var out = String('"')
    for codepoint in text.codepoints():
        var code = Int(codepoint.to_u32())
        if code == 0x22:
            out += '\\"'
        elif code == 0x5C:
            out += "\\\\"
        elif code == 0x0A:
            out += "\\n"
        elif code == 0x0D:
            out += "\\r"
        elif code == 0x09:
            out += "\\t"
        elif code == 0x08:
            out += "\\b"
        elif code == 0x0C:
            out += "\\f"
        elif code >= 0x20 and code <= 0x7E:
            out += chr(code)
        elif code > 0xFFFF:
            var value = code - 0x10000
            out += _unicode_escape(0xD800 | (value >> 10))
            out += _unicode_escape(0xDC00 | (value & 0x3FF))
        else:
            out += _unicode_escape(code)
    out += '"'
    return out^


def _unicode_escape(unit: Int) -> String:
    """Return `\\u` and four lowercase hexadecimal digits."""
    var out = String("\\u")
    for shift in [12, 8, 4, 0]:
        out += chr(Int(_HEX.as_bytes()[(unit >> shift) & 15]))
    return out^


struct JsonWriter(Movable):
    """Write JSON text as `json.dumps(value, indent=2)` does.

    Open an object or array, add members or items, and close it. Inside an
    object, call `key` before each value. An empty container is `{}` or
    `[]`.
    """

    var out: String
    """The text so far."""
    var counts: List[Int]
    """The number of entries in each open container."""
    var closers: List[String]
    """The closing bracket of each open container."""
    var keyed: Bool
    """True after `key`, until its value."""

    def __init__(out self):
        """Start an empty document."""
        self.out = String()
        self.counts = List[Int]()
        self.closers = List[String]()
        self.keyed = False

    def _newline(self) -> String:
        """Return a newline and the indentation of the current level."""
        return "\n" + _INDENT * len(self.counts)

    def _entry(mut self):
        """Start the next entry of the current container."""
        if self.keyed:
            self.keyed = False
            return
        if len(self.counts) == 0:
            return
        var last = len(self.counts) - 1
        if self.counts[last] > 0:
            self.out += ","
        self.counts[last] += 1
        self.out += self._newline()

    def _open(mut self, opener: String, closer: String):
        """Open a container."""
        self._entry()
        self.out += opener
        self.counts.append(0)
        self.closers.append(closer)

    def begin_object(mut self):
        """Open an object."""
        self._open("{", "}")

    def begin_array(mut self):
        """Open an array."""
        self._open("[", "]")

    def end(mut self):
        """Close the innermost container."""
        var count = self.counts.pop()
        var closer = self.closers.pop()
        if count > 0:
            self.out += self._newline()
        self.out += closer

    def key(mut self, name: String):
        """Start an object member.

        Args:
            name: The member name.
        """
        self._entry()
        self.out += quote_ascii(name) + ": "
        self.keyed = True

    def string(mut self, text: String):
        """Write a string.

        Args:
            text: The string.
        """
        self._entry()
        self.out += quote_ascii(text)

    def integer(mut self, value: Int):
        """Write an integer.

        Args:
            value: The integer.
        """
        self._entry()
        self.out += String(value)

    def number(mut self, value: Float64):
        """Write a float as Python's `repr` writes it: the shortest text that
        reads back to the same value, and `NaN` or `Infinity` as
        `json.dumps` writes them.

        Args:
            value: The number.
        """
        self._entry()
        if isnan(value):
            self.out += "NaN"
        elif isinf(value):
            self.out += "Infinity" if value > 0 else "-Infinity"
        else:
            # Mojo's own float text does not always read back exactly.
            try:
                self.out += python_repr(value)
            except:
                self.out += String(value)

    def boolean(mut self, value: Bool):
        """Write `true` or `false`.

        Args:
            value: The value.
        """
        self._entry()
        self.out += "true" if value else "false"

    def null(mut self):
        """Write `null`."""
        self._entry()
        self.out += "null"

    def node(mut self, document: JsonDocument, node: Int) raises:
        """Write a parsed value, keeping its member order.

        Args:
            document: The parsed document.
            node: A node, or `MISSING` for `null`.

        Raises:
            Error: If a number has a fraction, which the tools never hold.
        """
        if is_none(document, node):
            self.null()
            return
        var kind = document.kind(node)
        if kind == OBJECT:
            self.begin_object()
            for i in range(document.length(node)):
                var name = document.key(node, i)
                self.key(name)
                self.node(document, document.get(node, name))
            self.end()
        elif kind == ARRAY:
            self.begin_array()
            for i in range(document.length(node)):
                self.node(document, document.at(node, i))
            self.end()
        elif kind == STRING:
            self.string(document.string(node))
        elif kind == NUMBER:
            self.integer(document.integer(node))
        else:
            self.boolean(document.boolean(node))

    def text(self) -> String:
        """Return the finished text.

        Returns:
            The JSON text, without a final newline.
        """
        return self.out
