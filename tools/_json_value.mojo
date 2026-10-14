# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""JSON values that a tool can read, change and write as Python's `json` does.

A `JsonTree` holds many values. Each value is a node index. A tool builds
objects and arrays, changes members, and writes any node with the options of
`json.dumps`: an indent, sorted keys, and the two separators.

A number keeps the text that Python writes for it. An integer has any
number of digits, so a 64-bit hash stays exact. `parse` reads a float and
stores the text of its `repr`, so a value that a Python tool read and wrote
again has the same text here.

An object keeps the order in which its members were first set, as a Python
`dict` does. Setting a member again replaces its value in place.
"""

from tools._json_tools import quote_ascii
from tools._python_float import parse_float, python_repr

from loaders.json import (
    ARRAY,
    BOOLEAN,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    JsonKind,
)

comptime ABSENT = -1
"""The node index of a member that does not exist."""


def _less(a: String, b: String) -> Bool:
    """Return whether `a` sorts before `b` by code point, as Python sorts
    strings. UTF-8 byte order is code point order."""
    var x = a.as_bytes()
    var y = b.as_bytes()
    for i in range(min(len(x), len(y))):
        if x[i] != y[i]:
            return x[i] < y[i]
    return len(x) < len(y)


def sorted_strings(var names: List[String]) -> List[String]:
    """Return strings in Python's `sorted` order.

    Args:
        names: The strings.

    Returns:
        The strings sorted by code point.
    """
    # Insertion sort is stable and fast enough for object keys.
    for i in range(1, len(names)):
        var j = i
        while j > 0 and _less(names[j], names[j - 1]):
            names.swap_elements(j, j - 1)
            j -= 1
    return names^


def canonical_integer(text: String) raises -> String:
    """Return the text Python writes for `int(text)`.

    Args:
        text: Decimal digits with an optional sign and surrounding spaces.

    Returns:
        The digits without leading zeros, with `-` for a negative value.

    Raises:
        Error: `invalid literal for int()` when the text is not an integer.
    """
    var stripped = String(text.strip())
    var bytes = stripped.as_bytes()
    var start = 0
    var negative = False
    var first = Int(bytes[0]) if len(bytes) > 0 else 0
    if first == ord("-") or first == ord("+"):
        negative = first == ord("-")
        start = 1
    var valid = len(bytes) > start
    var digits = String()
    for i in range(start, len(bytes)):
        var byte = Int(bytes[i])
        if byte == ord("_"):
            # One underscore may sit between two digits.
            if (
                i == start
                or i + 1 == len(bytes)
                or Int(bytes[i - 1]) == ord("_")
            ):
                valid = False
        elif byte < ord("0") or byte > ord("9"):
            valid = False
        elif digits.byte_length() > 0 or byte != ord("0"):
            digits += chr(Int(byte))
    if not valid:
        raise Error(
            "invalid literal for int() with base 10: " + _python_quote(text)
        )
    if digits.byte_length() == 0:
        return "0"
    if negative:
        return "-" + digits
    return digits^


def _python_quote(text: String) -> String:
    """Return `repr(text)` for plain text, with single quotes."""
    if "'" in text and not ('"' in text):
        return '"' + text + '"'
    return "'" + text.replace("\\", "\\\\").replace("'", "\\'") + "'"


struct JsonTree(Movable):
    """JSON values, each a node index into this tree."""

    var kinds: List[JsonKind]
    """The kind of each node."""
    var texts: List[String]
    """The text of a string, a number or a Boolean."""
    var items: List[List[Int]]
    """The items of an array, or the values of an object's members."""
    var names: List[List[String]]
    """The member names of an object, in order."""

    def __init__(out self):
        """Make an empty tree."""
        self.kinds = List[JsonKind]()
        self.texts = List[String]()
        self.items = List[List[Int]]()
        self.names = List[List[String]]()

    def _add(mut self, kind: JsonKind, var text: String) -> Int:
        """Add a node and return its index."""
        self.kinds.append(kind)
        self.texts.append(text^)
        self.items.append(List[Int]())
        self.names.append(List[String]())
        return len(self.kinds) - 1

    def _check(self, node: Int) raises:
        """Raise if a node index is not in the tree."""
        if node < 0 or node >= len(self.kinds):
            raise Error("JSON node " + String(node) + " does not exist")

    # --- making values ------------------------------------------------------

    def null(mut self) -> Int:
        """Add `null`.

        Returns:
            The node.
        """
        return self._add(NULL, String("null"))

    def boolean(mut self, value: Bool) -> Int:
        """Add `true` or `false`.

        Args:
            value: The value.

        Returns:
            The node.
        """
        return self._add(BOOLEAN, String("true") if value else String("false"))

    def integer(mut self, value: Int) -> Int:
        """Add an integer.

        Args:
            value: The value.

        Returns:
            The node.
        """
        return self._add(NUMBER, String(value))

    def unsigned(mut self, value: UInt64) -> Int:
        """Add an unsigned 64-bit integer, such as a hash.

        Args:
            value: The value.

        Returns:
            The node.
        """
        return self._add(NUMBER, String(value))

    def integer_text(mut self, text: String) raises -> Int:
        """Add an integer from its decimal text, as `int(text)` reads it.

        Args:
            text: The digits.

        Returns:
            The node.

        Raises:
            Error: If the text is not an integer.
        """
        return self._add(NUMBER, canonical_integer(text))

    def number(mut self, value: Float64) raises -> Int:
        """Add a float, written as Python's `repr` writes it.

        Args:
            value: The value.

        Returns:
            The node.

        Raises:
            Error: If the shortest digits cannot be found.
        """
        if value != value:
            return self._add(NUMBER, String("NaN"))
        if value - value != 0:
            return self._add(
                NUMBER, String("Infinity") if value > 0 else String("-Infinity")
            )
        return self._add(NUMBER, python_repr(value))

    def string(mut self, text: String) -> Int:
        """Add a string.

        Args:
            text: The string.

        Returns:
            The node.
        """
        return self._add(STRING, text.copy())

    def array(mut self) -> Int:
        """Add an empty array.

        Returns:
            The node.
        """
        return self._add(ARRAY, String())

    def object(mut self) -> Int:
        """Add an empty object.

        Returns:
            The node.
        """
        return self._add(OBJECT, String())

    def strings(mut self, values: List[String]) -> Int:
        """Add an array of strings.

        Args:
            values: The strings.

        Returns:
            The node.
        """
        var node = self.array()
        for value in values:
            var child = self.string(value)
            self.items[node].append(child)
        return node

    def integers(mut self, values: List[Int]) -> Int:
        """Add an array of integers.

        Args:
            values: The integers.

        Returns:
            The node.
        """
        var node = self.array()
        for value in values:
            var child = self.integer(value)
            self.items[node].append(child)
        return node

    # --- changing values ----------------------------------------------------

    def append(mut self, array: Int, value: Int) raises:
        """Append an item to an array.

        Args:
            array: The array.
            value: The item's node.

        Raises:
            Error: If `array` is not an array.
        """
        self._check(array)
        if self.kinds[array] != ARRAY:
            raise Error("JSON node is not an array")
        self.items[array].append(value)

    def set(mut self, object: Int, name: String, value: Int) raises:
        """Set a member, as `dict[name] = value` does.

        A new member goes last. An existing member keeps its place.

        Args:
            object: The object.
            name: The member name.
            value: The member's node.

        Raises:
            Error: If `object` is not an object.
        """
        self._check(object)
        if self.kinds[object] != OBJECT:
            raise Error("JSON node is not an object")
        for i in range(len(self.names[object])):
            if self.names[object][i] == name:
                self.items[object][i] = value
                return
        self.names[object].append(name)
        self.items[object].append(value)

    def remove(mut self, object: Int, name: String) raises:
        """Remove a member when it exists.

        Args:
            object: The object.
            name: The member name.

        Raises:
            Error: If `object` is not an object.
        """
        self._check(object)
        if self.kinds[object] != OBJECT:
            raise Error("JSON node is not an object")
        for i in range(len(self.names[object])):
            if self.names[object][i] == name:
                _ = self.names[object].pop(i)
                _ = self.items[object].pop(i)
                return

    # --- reading values -----------------------------------------------------

    def kind(self, node: Int) raises -> JsonKind:
        """Return a node's kind.

        Args:
            node: The node.

        Returns:
            Its kind.

        Raises:
            Error: If the node does not exist.
        """
        self._check(node)
        return self.kinds[node]

    def text(self, node: Int) raises -> String:
        """Return the text of a string, number or Boolean.

        Args:
            node: The node.

        Returns:
            The string itself, or the number's Python text.

        Raises:
            Error: If the node does not exist.
        """
        self._check(node)
        return self.texts[node]

    def length(self, node: Int) raises -> Int:
        """Return the number of items or members.

        Args:
            node: An array or object.

        Returns:
            The count.

        Raises:
            Error: If the node does not exist.
        """
        self._check(node)
        return len(self.items[node])

    def at(self, node: Int, index: Int) raises -> Int:
        """Return an array item or an object member's value by position.

        Args:
            node: An array or object.
            index: The position.

        Returns:
            The item's node.

        Raises:
            Error: If the position is out of range.
        """
        self._check(node)
        if index < 0 or index >= len(self.items[node]):
            raise Error("list index out of range")
        return self.items[node][index]

    def keys(self, node: Int) raises -> List[String]:
        """Return an object's member names in order.

        Args:
            node: An object.

        Returns:
            The names.

        Raises:
            Error: If the node does not exist.
        """
        self._check(node)
        return self.names[node].copy()

    def find(self, node: Int, name: String) raises -> Int:
        """Return a member as `dict.get` does.

        Args:
            node: Any node.
            name: The member name.

        Returns:
            The member's node, or `ABSENT`.

        Raises:
            Error: If the node does not exist.
        """
        self._check(node)
        if self.kinds[node] != OBJECT:
            return ABSENT
        for i in range(len(self.names[node])):
            if self.names[node][i] == name:
                return self.items[node][i]
        return ABSENT

    def get(self, node: Int, name: String) raises -> Int:
        """Return a member as `dict[name]` does.

        Args:
            node: An object.
            name: The member name.

        Returns:
            The member's node.

        Raises:
            Error: `'name'`, as Python's `KeyError` prints, when absent.
        """
        var found = self.find(node, name)
        if found == ABSENT:
            raise Error("'" + name + "'")
        return found

    def is_integer(self, node: Int) raises -> Bool:
        """Return whether a node is an integer number.

        Args:
            node: The node.

        Returns:
            True for a number without a fraction or exponent part.

        Raises:
            Error: If the node does not exist.
        """
        self._check(node)
        if self.kinds[node] != NUMBER:
            return False
        for value in self.texts[node].as_bytes():
            var byte = Int(value)
            if not (
                byte == ord("-") or (byte >= ord("0") and byte <= ord("9"))
            ):
                return False
        return True

    def int_value(self, node: Int) raises -> Int:
        """Return an integer member as a machine integer.

        Args:
            node: An integer node.

        Returns:
            The value.

        Raises:
            Error: If the node is not an integer that fits 64 bits.
        """
        if not self.is_integer(node):
            raise Error("JSON value is not an integer: " + self.texts[node])
        return Int(self.texts[node])

    def float_value(self, node: Int) raises -> Float64:
        """Return a number as a double, as `float(value)` does.

        Args:
            node: A number node.

        Returns:
            The nearest double.

        Raises:
            Error: If the node is not a number.
        """
        self._check(node)
        if self.kinds[node] != NUMBER:
            raise Error("JSON value is not a number")
        var text = self.texts[node]
        if text == "NaN":
            return Float64.MAX * 2 - Float64.MAX * 2
        if text == "Infinity":
            return Float64.MAX * 2
        if text == "-Infinity":
            return -(Float64.MAX * 2)
        return parse_float(text)

    def string_value(self, node: Int) raises -> String:
        """Return a string node's text.

        Args:
            node: A string node.

        Returns:
            The text.

        Raises:
            Error: If the node is not a string.
        """
        self._check(node)
        if self.kinds[node] != STRING:
            raise Error("JSON value is not a string")
        return self.texts[node]

    def truthy(self, node: Int) raises -> Bool:
        """Return the Python truth value of a node.

        Args:
            node: A node or `ABSENT`.

        Returns:
            False for `ABSENT`, `null`, `false`, zero and empty values.

        Raises:
            Error: If the node does not exist.
        """
        if node == ABSENT:
            return False
        self._check(node)
        var kind = self.kinds[node]
        if kind == NULL:
            return False
        if kind == BOOLEAN:
            return self.texts[node] == "true"
        if kind == NUMBER:
            return self.float_value(node) != 0
        if kind == STRING:
            return self.texts[node].byte_length() > 0
        return len(self.items[node]) > 0

    def equal(self, a: Int, b: Int) raises -> Bool:
        """Return whether two nodes are equal under Python's `==`.

        Args:
            a: A node.
            b: A node.

        Returns:
            True for equal values. Numbers compare by value.

        Raises:
            Error: If a node does not exist.
        """
        self._check(a)
        self._check(b)
        var ka = self.kinds[a]
        var kb = self.kinds[b]
        if (ka == NUMBER or ka == BOOLEAN) and (kb == NUMBER or kb == BOOLEAN):
            if self.texts[a] == self.texts[b]:
                return True
            if self.is_integer(a) and self.is_integer(b):
                return False
            return self._numeric(a) == self._numeric(b)
        if ka != kb:
            return False
        if ka == NULL:
            return True
        if ka == STRING:
            return self.texts[a] == self.texts[b]
        if len(self.items[a]) != len(self.items[b]):
            return False
        if ka == ARRAY:
            for i in range(len(self.items[a])):
                if not self.equal(self.items[a][i], self.items[b][i]):
                    return False
            return True
        for i in range(len(self.names[a])):
            var other = self.find(b, self.names[a][i])
            if other == ABSENT or not self.equal(self.items[a][i], other):
                return False
        return True

    def _numeric(self, node: Int) raises -> Float64:
        """Return a number or Boolean as Python compares it."""
        if self.kinds[node] == BOOLEAN:
            return 1.0 if self.texts[node] == "true" else 0.0
        return self.float_value(node)

    # --- writing ------------------------------------------------------------

    def dumps(
        self,
        node: Int,
        indent: Int = -1,
        sort_keys: Bool = False,
        item_separator: String = ", ",
        key_separator: String = ": ",
    ) raises -> String:
        """Return a node's text as `json.dumps` writes it.

        Args:
            node: The node.
            indent: The indent width, or -1 for `indent=None`.
            sort_keys: True to write members in sorted order.
            item_separator: The text between items. Python uses `,` when an
                indent is given.
            key_separator: The text between a name and its value.

        Returns:
            The text, with every character outside printable ASCII escaped.

        Raises:
            Error: If the node does not exist.
        """
        var out = String()
        self._write(
            out, node, indent, sort_keys, item_separator, key_separator, 0
        )
        return out^

    def _write(
        self,
        mut out: String,
        node: Int,
        indent: Int,
        sort_keys: Bool,
        item_separator: String,
        key_separator: String,
        depth: Int,
    ) raises:
        """Append a node's text."""
        self._check(node)
        var kind = self.kinds[node]
        if kind == STRING:
            out += quote_ascii(self.texts[node])
            return
        if kind != ARRAY and kind != OBJECT:
            out += self.texts[node]
            return
        var count = len(self.items[node])
        if count == 0:
            out += "[]" if kind == ARRAY else "{}"
            return
        out += "[" if kind == ARRAY else "{"
        var inner = String()
        var outer = String()
        if indent >= 0:
            inner = "\n" + String(" ") * (indent * (depth + 1))
            outer = "\n" + String(" ") * (indent * depth)
        var order = List[Int]()
        if kind == OBJECT and sort_keys:
            var sorted = sorted_strings(self.names[node].copy())
            for name in sorted:
                for i in range(count):
                    if self.names[node][i] == name:
                        order.append(i)
                        break
        else:
            for i in range(count):
                order.append(i)
        for position in range(count):
            var i = order[position]
            if position > 0:
                out += item_separator
            out += inner
            if kind == OBJECT:
                out += quote_ascii(self.names[node][i])
                out += key_separator
            self._write(
                out,
                self.items[node][i],
                indent,
                sort_keys,
                item_separator,
                key_separator,
                depth + 1,
            )
        out += outer
        out += "]" if kind == ARRAY else "}"

    # --- reading ------------------------------------------------------------

    def parse(mut self, text: String) raises -> Int:
        """Read JSON text into this tree, as `json.loads` reads it.

        Args:
            text: The JSON text.

        Returns:
            The root node.

        Raises:
            Error: If the text is not one JSON value.
        """
        var reader = _Reader(text)
        reader.space()
        var root = reader.value(self, 0)
        reader.space()
        if reader.at < len(reader.bytes):
            raise Error("Extra data at byte " + String(reader.at))
        return root


struct _Reader(Movable):
    """A position in JSON text."""

    var bytes: List[UInt8]
    var at: Int

    def __init__(out self, text: String):
        self.bytes = List[UInt8](text.as_bytes())
        self.at = 0

    def space(mut self):
        while self.at < len(self.bytes):
            var byte = Int(self.bytes[self.at])
            if (
                byte == ord(" ")
                or byte == ord("\t")
                or byte == ord("\n")
                or byte == ord("\r")
            ):
                self.at += 1
            else:
                return

    def fail(self, what: String) -> Error:
        return Error(what + " at byte " + String(self.at))

    def peek(self) -> Int:
        if self.at >= len(self.bytes):
            return -1
        return Int(self.bytes[self.at])

    def word(mut self, word: String) -> Bool:
        var expected = word.as_bytes()
        if self.at + len(expected) > len(self.bytes):
            return False
        for i in range(len(expected)):
            if self.bytes[self.at + i] != expected[i]:
                return False
        self.at += len(expected)
        return True

    def value(mut self, mut tree: JsonTree, depth: Int) raises -> Int:
        if depth > 1000:
            raise self.fail("JSON nesting is too deep")
        var byte = self.peek()
        if byte == ord("{"):
            self.at += 1
            var node = tree.object()
            self.space()
            if self.peek() == ord("}"):
                self.at += 1
                return node
            while True:
                self.space()
                if self.peek() != ord('"'):
                    raise self.fail("Expecting property name")
                var name = self.string()
                self.space()
                if self.peek() != ord(":"):
                    raise self.fail("Expecting ':' delimiter")
                self.at += 1
                self.space()
                var child = self.value(tree, depth + 1)
                tree.set(node, name, child)
                self.space()
                if self.peek() == ord(","):
                    self.at += 1
                    continue
                if self.peek() == ord("}"):
                    self.at += 1
                    return node
                raise self.fail("Expecting ',' delimiter")
        if byte == ord("["):
            self.at += 1
            var node = tree.array()
            self.space()
            if self.peek() == ord("]"):
                self.at += 1
                return node
            while True:
                self.space()
                var child = self.value(tree, depth + 1)
                tree.items[node].append(child)
                self.space()
                if self.peek() == ord(","):
                    self.at += 1
                    continue
                if self.peek() == ord("]"):
                    self.at += 1
                    return node
                raise self.fail("Expecting ',' delimiter")
        if byte == ord('"'):
            return tree.string(self.string())
        if self.word("null"):
            return tree.null()
        if self.word("true"):
            return tree.boolean(True)
        if self.word("false"):
            return tree.boolean(False)
        if self.word("NaN"):
            return tree._add(NUMBER, String("NaN"))
        if self.word("Infinity"):
            return tree._add(NUMBER, String("Infinity"))
        if self.word("-Infinity"):
            return tree._add(NUMBER, String("-Infinity"))
        return self.number(tree)

    def number(mut self, mut tree: JsonTree) raises -> Int:
        var start = self.at
        if self.peek() == ord("-"):
            self.at += 1
        var digits = self.at
        while self.peek() >= ord("0") and self.peek() <= ord("9"):
            self.at += 1
        if self.at == digits:
            raise self.fail("Expecting value")
        if Int(self.bytes[digits]) == ord("0") and self.at - digits > 1:
            # JSON forbids leading zeros; Python stops after the zero.
            self.at = digits + 1
        var fraction = False
        if self.peek() == ord("."):
            var mark = self.at
            self.at += 1
            var first = self.at
            while self.peek() >= ord("0") and self.peek() <= ord("9"):
                self.at += 1
            if self.at == first:
                self.at = mark
            else:
                fraction = True
        if self.peek() == ord("e") or self.peek() == ord("E"):
            var mark = self.at
            self.at += 1
            if self.peek() == ord("+") or self.peek() == ord("-"):
                self.at += 1
            var first = self.at
            while self.peek() >= ord("0") and self.peek() <= ord("9"):
                self.at += 1
            if self.at == first:
                self.at = mark
            else:
                fraction = True
        var text = String(
            StringSlice(unsafe_from_utf8=Span(self.bytes)[start : self.at])
        )
        if fraction:
            return tree.number(parse_float(text))
        return tree._add(NUMBER, canonical_integer(text))

    def hex4(mut self) raises -> Int:
        if self.at + 4 > len(self.bytes):
            raise self.fail("Invalid \\uXXXX escape")
        var value = 0
        for _ in range(4):
            var byte = Int(self.bytes[self.at])
            var digit: Int
            if byte >= ord("0") and byte <= ord("9"):
                digit = byte - ord("0")
            elif byte >= ord("a") and byte <= ord("f"):
                digit = byte - ord("a") + 10
            elif byte >= ord("A") and byte <= ord("F"):
                digit = byte - ord("A") + 10
            else:
                raise self.fail("Invalid \\uXXXX escape")
            value = value * 16 + digit
            self.at += 1
        return value

    def string(mut self) raises -> String:
        self.at += 1
        var out = List[UInt8]()
        while True:
            if self.at >= len(self.bytes):
                raise self.fail("Unterminated string")
            var byte = Int(self.bytes[self.at])
            if byte == ord('"'):
                self.at += 1
                break
            if byte < 0x20:
                raise self.fail("Invalid control character")
            if byte != ord("\\"):
                out.append(UInt8(byte))
                self.at += 1
                continue
            self.at += 1
            var letter = self.peek()
            self.at += 1
            if letter == ord('"') or letter == ord("\\") or letter == ord("/"):
                out.append(UInt8(letter))
            elif letter == ord("b"):
                out.append(8)
            elif letter == ord("f"):
                out.append(12)
            elif letter == ord("n"):
                out.append(10)
            elif letter == ord("r"):
                out.append(13)
            elif letter == ord("t"):
                out.append(9)
            elif letter == ord("u"):
                var code = self.hex4()
                if (
                    code >= 0xD800
                    and code < 0xDC00
                    and self.peek() == ord("\\")
                    and self.at + 1 < len(self.bytes)
                    and Int(self.bytes[self.at + 1]) == ord("u")
                ):
                    var mark = self.at
                    self.at += 2
                    var low = self.hex4()
                    if low >= 0xDC00 and low < 0xE000:
                        code = (
                            0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        )
                    else:
                        self.at = mark
                _utf8(out, code)
            else:
                raise self.fail("Invalid \\escape")
        return String(unsafe_from_utf8=out^)


def _utf8(mut out: List[UInt8], code: Int):
    """Append a code point as UTF-8."""
    if code < 0x80:
        out.append(UInt8(code))
    elif code < 0x800:
        out.append(UInt8(0xC0 | (code >> 6)))
        out.append(UInt8(0x80 | (code & 0x3F)))
    elif code < 0x10000:
        out.append(UInt8(0xE0 | (code >> 12)))
        out.append(UInt8(0x80 | ((code >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (code & 0x3F)))
    else:
        out.append(UInt8(0xF0 | (code >> 18)))
        out.append(UInt8(0x80 | ((code >> 12) & 0x3F)))
        out.append(UInt8(0x80 | ((code >> 6) & 0x3F)))
        out.append(UInt8(0x80 | (code & 0x3F)))
