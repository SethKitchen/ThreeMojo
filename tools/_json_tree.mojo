# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A JSON tree that a tool can change, with the values of Python's `json`.

A ported tool that reads JSON, changes it and writes it again needs three
things that `loaders.json` does not give:

- An int and a float stay apart. `json.loads` reads `0` as an int and `0.0`
  as a float, and `json.dumps` writes each one back the same way.
- A float is the nearest double to its text, and it is written with the
  digits of Python's `repr`.
- An object keeps its member order. Setting a member it has keeps that
  member's place; a new member goes last, as in a Python `dict`.

Every value lives in one `JsonTree` and is named by its index. A value can
be the child of more than one container: `json.dumps` writes it each time.
`NOTHING` stands for a missing value and acts as Python's `None`.

A lone UTF-16 surrogate escape reads as U+FFFD, because a Mojo `String`
cannot hold it. Python keeps the surrogate.
"""

from std.math import isinf, isnan
from std.memory import bitcast

from loaders.json import (
    ARRAY,
    BOOLEAN,
    NULL,
    NUMBER,
    OBJECT,
    STRING,
    JsonKind,
)
from tools._json_tools import quote_ascii
from tools._python_float import parse_float, python_repr

comptime NOTHING = -1
"""The index of a missing value. It acts as Python's `None`."""
comptime MAX_DEPTH = 900
"""How deep a parsed value can nest, about where Python's recursion stops."""
comptime _POWERS = [
    1.0,
    10.0,
    100.0,
    1e3,
    1e4,
    1e5,
    1e6,
    1e7,
    1e8,
    1e9,
    1e10,
    1e11,
    1e12,
    1e13,
    1e14,
    1e15,
    1e16,
    1e17,
    1e18,
    1e19,
    1e20,
    1e21,
    1e22,
]
"""The powers of ten that a double holds exactly."""


@fieldwise_init
struct JsonValue(Copyable, Movable):
    """One value of a tree."""

    var kind: JsonKind
    """What the value is."""
    var integral: Bool
    """True for a number that is a Python int."""
    var number: Float64
    """A float's value."""
    var integer: Int
    """An int's value, or a Boolean as 0 or 1."""
    var text: String
    """A string's text."""
    var items: List[Int]
    """An array's items, or an object's member values."""
    var names: List[String]
    """An object's member names, in order."""


def type_name(tree: JsonTree, node: Int) raises -> String:
    """Return the Python type name of a value, for an error message.

    Args:
        tree: The tree.
        node: A value or `NOTHING`.

    Returns:
        `NoneType`, `bool`, `int`, `float`, `str`, `list` or `dict`.

    Raises:
        Error: If `node` is not a value of `tree`.
    """
    var kind = tree.kind(node)
    if kind == NULL:
        return "NoneType"
    if kind == BOOLEAN:
        return "bool"
    if kind == NUMBER:
        return "int" if tree.is_int(node) else "float"
    if kind == STRING:
        return "str"
    if kind == ARRAY:
        return "list"
    return "dict"


struct JsonTree(Movable):
    """Values that refer to each other by index."""

    var values: List[JsonValue]
    """Every value."""
    var reprs: Dict[UInt64, String]
    """The written text of each float written so far, by its bits."""

    def __init__(out self):
        """Start an empty tree."""
        self.values = List[JsonValue]()
        self.reprs = Dict[UInt64, String]()

    # --- making values ------------------------------------------------------

    def _add(mut self, kind: JsonKind) -> Int:
        """Add an empty value of a kind, and return its index."""
        self.values.append(
            JsonValue(
                kind, False, 0.0, 0, String(), List[Int](), List[String]()
            )
        )
        return len(self.values) - 1

    def null(mut self) -> Int:
        """Add `None`.

        Returns:
            Its index.
        """
        return self._add(NULL)

    def boolean(mut self, flag: Bool) -> Int:
        """Add a Boolean.

        Args:
            flag: The value.

        Returns:
            Its index.
        """
        var node = self._add(BOOLEAN)
        self.values[node].integer = 1 if flag else 0
        return node

    def integer(mut self, value: Int) -> Int:
        """Add an int.

        Args:
            value: The value.

        Returns:
            Its index.
        """
        var node = self._add(NUMBER)
        self.values[node].integral = True
        self.values[node].integer = value
        self.values[node].number = Float64(value)
        return node

    def number(mut self, value: Float64) -> Int:
        """Add a float.

        Args:
            value: The value.

        Returns:
            Its index.
        """
        var node = self._add(NUMBER)
        self.values[node].number = value
        return node

    def string(mut self, text: String) -> Int:
        """Add a string.

        Args:
            text: The text.

        Returns:
            Its index.
        """
        var node = self._add(STRING)
        self.values[node].text = text
        return node

    def array(mut self) -> Int:
        """Add an empty array.

        Returns:
            Its index.
        """
        return self._add(ARRAY)

    def object(mut self) -> Int:
        """Add an empty object.

        Returns:
            Its index.
        """
        return self._add(OBJECT)

    def numbers(mut self, values: List[Float64]) -> Int:
        """Add an array of floats.

        Args:
            values: The floats.

        Returns:
            The array's index.
        """
        var node = self.array()
        for value in values:
            var item = self.number(value)
            self.values[node].items.append(item)
        return node

    def strings(mut self, texts: List[String]) -> Int:
        """Add an array of strings.

        Args:
            texts: The strings.

        Returns:
            The array's index.
        """
        var node = self.array()
        for text in texts:
            var item = self.string(text)
            self.values[node].items.append(item)
        return node

    # --- reading values -----------------------------------------------------

    def _check(self, node: Int) raises:
        """Refuse an index that names no value."""
        if node < 0 or node >= len(self.values):
            raise Error("JSON tree: no value at index " + String(node))

    def kind(self, node: Int) raises -> JsonKind:
        """Return what a value is.

        Args:
            node: A value or `NOTHING`.

        Returns:
            Its kind. `NOTHING` is `NULL`.

        Raises:
            Error: If `node` is not a value of the tree.
        """
        if node == NOTHING:
            return NULL
        self._check(node)
        return self.values[node].kind

    def is_null(self, node: Int) raises -> Bool:
        """Return whether a value is `None`.

        Args:
            node: A value or `NOTHING`.

        Returns:
            True for `NOTHING` and `null`.

        Raises:
            Error: If `node` is not a value of the tree.
        """
        return self.kind(node) == NULL

    def is_int(self, node: Int) raises -> Bool:
        """Return whether a value is a Python int, which a Boolean is not.

        Args:
            node: A value or `NOTHING`.

        Returns:
            True for an int.

        Raises:
            Error: If `node` is not a value of the tree.
        """
        return self.kind(node) == NUMBER and self.values[node].integral

    def is_float(self, node: Int) raises -> Bool:
        """Return whether a value is a float.

        Args:
            node: A value or `NOTHING`.

        Returns:
            True for a float.

        Raises:
            Error: If `node` is not a value of the tree.
        """
        return self.kind(node) == NUMBER and not self.values[node].integral

    def is_numeric(self, node: Int) raises -> Bool:
        """Return whether a value takes part in arithmetic, as a Boolean,
        an int and a float do in Python.

        Args:
            node: A value or `NOTHING`.

        Returns:
            True for a number or a Boolean.

        Raises:
            Error: If `node` is not a value of the tree.
        """
        var kind = self.kind(node)
        return kind == NUMBER or kind == BOOLEAN

    def value(self, node: Int) raises -> Float64:
        """Return a number as a float, with a Boolean as 0 or 1.

        Args:
            node: A value or `NOTHING`.

        Returns:
            The value.

        Raises:
            Error: If the value is not a number or a Boolean.
        """
        var kind = self.kind(node)
        if kind == BOOLEAN:
            return Float64(self.values[node].integer)
        if kind != NUMBER:
            raise Error(
                "unsupported operand type for a number: '"
                + type_name(self, node)
                + "'"
            )
        if self.values[node].integral:
            return Float64(self.values[node].integer)
        return self.values[node].number

    def int_value(self, node: Int) raises -> Int:
        """Return an int.

        Args:
            node: An int or a Boolean.

        Returns:
            The value.

        Raises:
            Error: If the value is not an int or a Boolean.
        """
        var kind = self.kind(node)
        if kind == BOOLEAN or (kind == NUMBER and self.values[node].integral):
            return self.values[node].integer
        raise Error("expected an int, not '" + type_name(self, node) + "'")

    def flag(self, node: Int) raises -> Bool:
        """Return a Boolean.

        Args:
            node: A Boolean.

        Returns:
            The value.

        Raises:
            Error: If the value is not a Boolean.
        """
        if self.kind(node) != BOOLEAN:
            raise Error("expected a bool, not '" + type_name(self, node) + "'")
        return self.values[node].integer != 0

    def text(self, node: Int) raises -> String:
        """Return a string's text.

        Args:
            node: A string.

        Returns:
            The text.

        Raises:
            Error: If the value is not a string.
        """
        if self.kind(node) != STRING:
            raise Error(
                "'" + type_name(self, node) + "' object is not a string"
            )
        return self.values[node].text

    def is_text(self, node: Int, text: String) raises -> Bool:
        """Return whether a value is a given string, as Python's `==`.

        Args:
            node: A value or `NOTHING`.
            text: The string.

        Returns:
            True for a string with that text.

        Raises:
            Error: If `node` is not a value of the tree.
        """
        return self.kind(node) == STRING and self.values[node].text == text

    def is_number(self, node: Int, number: Float64) raises -> Bool:
        """Return whether a value equals a number, as Python's `==`.

        Args:
            node: A value or `NOTHING`.
            number: The number.

        Returns:
            True for an equal number or Boolean.

        Raises:
            Error: If `node` is not a value of the tree.
        """
        return self.is_numeric(node) and self.value(node) == number

    def length(self, node: Int) raises -> Int:
        """Return the number of items, members or characters.

        Args:
            node: An array, an object or a string.

        Returns:
            The length, as Python's `len`.

        Raises:
            Error: If the value has no length.
        """
        var kind = self.kind(node)
        if kind == ARRAY or kind == OBJECT:
            return len(self.values[node].items)
        if kind == STRING:
            var count = 0
            for _ in self.values[node].text.codepoints():
                count += 1
            return count
        raise Error(
            "object of type '" + type_name(self, node) + "' has no len()"
        )

    def at(self, node: Int, index: Int) raises -> Int:
        """Return an array item, or an object's member value by position.

        Args:
            node: An array or an object.
            index: The position, from zero. A negative position counts from
                the end.

        Returns:
            The item.

        Raises:
            Error: If the value is not a container or the position is out
                of range.
        """
        var kind = self.kind(node)
        if kind != ARRAY and kind != OBJECT:
            raise Error(
                "'" + type_name(self, node) + "' object is not subscriptable"
            )
        var count = len(self.values[node].items)
        var position = index + count if index < 0 else index
        if position < 0 or position >= count:
            raise Error("list index out of range")
        return self.values[node].items[position]

    def name(self, node: Int, index: Int) raises -> String:
        """Return an object's member name by position.

        Args:
            node: An object.
            index: The position, from zero.

        Returns:
            The name.

        Raises:
            Error: If the value is not an object or the position is out of
                range.
        """
        if self.kind(node) != OBJECT:
            raise Error("'" + type_name(self, node) + "' object has no keys")
        if index < 0 or index >= len(self.values[node].names):
            raise Error("member index out of range")
        return self.values[node].names[index]

    def items(self, node: Int) raises -> List[Int]:
        """Return the items of an array, or the member values of an object.

        Args:
            node: An array or an object.

        Returns:
            A copy of the indices, in order.

        Raises:
            Error: If the value is not a container.
        """
        var kind = self.kind(node)
        if kind != ARRAY and kind != OBJECT:
            raise Error(
                "'" + type_name(self, node) + "' object is not iterable"
            )
        return self.values[node].items.copy()

    def names(self, node: Int) raises -> List[String]:
        """Return an object's member names.

        Args:
            node: An object.

        Returns:
            A copy of the names, in order.

        Raises:
            Error: If the value is not an object.
        """
        if self.kind(node) != OBJECT:
            raise Error("'" + type_name(self, node) + "' object has no keys")
        return self.values[node].names.copy()

    def _find(self, node: Int, key: String) -> Int:
        """Return a member's position, or -1."""
        for index in range(len(self.values[node].names)):
            if self.values[node].names[index] == key:
                return index
        return -1

    def get(self, node: Int, key: String) raises -> Int:
        """Return a member as `dict.get` does.

        Args:
            node: An object.
            key: The member name.

        Returns:
            The member, or `NOTHING` when the object has no such member.

        Raises:
            Error: If the value is not an object, as Python has no `get`
                for it.
        """
        if self.kind(node) != OBJECT:
            raise Error(
                "'" + type_name(self, node) + "' object has no attribute 'get'"
            )
        var position = self._find(node, key)
        if position < 0:
            return NOTHING
        return self.values[node].items[position]

    def has(self, node: Int, key: String) raises -> Bool:
        """Return whether an object has a member.

        Args:
            node: An object.
            key: The member name.

        Returns:
            True when the member is there.

        Raises:
            Error: If the value is not an object.
        """
        return self.get(node, key) != NOTHING

    def item(self, node: Int, key: String) raises -> Int:
        """Return a member as `dict[key]` does.

        Args:
            node: An object.
            key: The member name.

        Returns:
            The member.

        Raises:
            Error: `'key'`, as Python's `KeyError` prints, when the member
                is absent, or a type error when the value is not an object.
        """
        var kind = self.kind(node)
        if kind != OBJECT:
            if kind == ARRAY:
                raise Error("list indices must be integers or slices, not str")
            raise Error(
                "'" + type_name(self, node) + "' object is not subscriptable"
            )
        var position = self._find(node, key)
        if position < 0:
            raise Error("'" + key + "'")
        return self.values[node].items[position]

    def path(self, node: Int, keys: List[String]) raises -> Int:
        """Return a nested member, as `value[a][b]...` does.

        Args:
            node: An object.
            keys: The member names, outermost first.

        Returns:
            The nested member.

        Raises:
            Error: If a member is absent or a value is not an object.
        """
        var found = node
        for key in keys:
            found = self.item(found, key)
        return found

    # --- changing values ----------------------------------------------------

    def append(mut self, node: Int, child: Int) raises:
        """Add an item to the end of an array.

        Args:
            node: An array.
            child: The item.

        Raises:
            Error: If the value is not an array.
        """
        if self.kind(node) != ARRAY:
            raise Error(
                "'"
                + type_name(self, node)
                + "' object has no attribute 'append'"
            )
        self.values[node].items.append(child)

    def set(mut self, node: Int, key: String, child: Int) raises:
        """Set a member as `value[key] = child` does: in place when the
        member is there, and last otherwise.

        Args:
            node: An object.
            key: The member name.
            child: The member value.

        Raises:
            Error: If the value is not an object.
        """
        if self.kind(node) != OBJECT:
            raise Error(
                "'"
                + type_name(self, node)
                + "' object does not support item assignment"
            )
        var position = self._find(node, key)
        if position >= 0:
            self.values[node].items[position] = child
            return
        self.values[node].names.append(key)
        self.values[node].items.append(child)

    def set_text(mut self, node: Int, key: String, text: String) raises:
        """Set a member to a string.

        Args:
            node: An object.
            key: The member name.
            text: The string.

        Raises:
            Error: If the value is not an object.
        """
        var child = self.string(text)
        self.set(node, key, child)

    def set_flag(mut self, node: Int, key: String, flag: Bool) raises:
        """Set a member to a Boolean.

        Args:
            node: An object.
            key: The member name.
            flag: The value.

        Raises:
            Error: If the value is not an object.
        """
        var child = self.boolean(flag)
        self.set(node, key, child)

    def set_null(mut self, node: Int, key: String) raises:
        """Set a member to `None`.

        Args:
            node: An object.
            key: The member name.

        Raises:
            Error: If the value is not an object.
        """
        var child = self.null()
        self.set(node, key, child)

    def delete(mut self, node: Int, key: String) raises:
        """Remove a member as `del value[key]` does.

        Args:
            node: An object.
            key: The member name.

        Raises:
            Error: `'key'` when the member is absent, or a type error when
                the value is not an object.
        """
        _ = self.item(node, key)
        _ = self.pop(node, key)

    def pop(mut self, node: Int, key: String) raises -> Int:
        """Remove a member as `value.pop(key, None)` does.

        Args:
            node: An object.
            key: The member name.

        Returns:
            The removed member, or `NOTHING`.

        Raises:
            Error: If the value is not an object.
        """
        if self.kind(node) != OBJECT:
            raise Error(
                "'" + type_name(self, node) + "' object has no attribute 'pop'"
            )
        var position = self._find(node, key)
        if position < 0:
            return NOTHING
        var child = self.values[node].items.pop(position)
        _ = self.values[node].names.pop(position)
        return child

    def drop_last(mut self, node: Int) raises -> Int:
        """Remove the last item of an array, as `list.pop()` does.

        Args:
            node: A nonempty array.

        Returns:
            The removed item.

        Raises:
            Error: If the value is not an array or is empty.
        """
        if self.kind(node) != ARRAY:
            raise Error("'" + type_name(self, node) + "' object is not a list")
        if len(self.values[node].items) == 0:
            raise Error("pop from empty list")
        return self.values[node].items.pop()

    def remove_at(mut self, node: Int, index: Int) raises -> Int:
        """Remove an array item, as `list.pop(index)` does.

        Args:
            node: An array.
            index: The position.

        Returns:
            The removed item.

        Raises:
            Error: If the value is not an array or the position is out of
                range.
        """
        if self.kind(node) != ARRAY:
            raise Error("'" + type_name(self, node) + "' object is not a list")
        if index < 0 or index >= len(self.values[node].items):
            raise Error("pop index out of range")
        return self.values[node].items.pop(index)

    def insert(mut self, node: Int, index: Int, child: Int) raises:
        """Insert an array item, as `list.insert(index, child)` does.

        Args:
            node: An array.
            index: The position, from zero.
            child: The item.

        Raises:
            Error: If the value is not an array.
        """
        if self.kind(node) != ARRAY:
            raise Error("'" + type_name(self, node) + "' object is not a list")
        self.values[node].items.insert(index, child)

    def replace(mut self, node: Int, index: Int, child: Int) raises:
        """Replace an array item, as `value[index] = child` does.

        Args:
            node: An array.
            index: The position, from zero.
            child: The new item.

        Raises:
            Error: If the value is not an array or the position is out of
                range.
        """
        if self.kind(node) != ARRAY:
            raise Error("'" + type_name(self, node) + "' object is not a list")
        if index < 0 or index >= len(self.values[node].items):
            raise Error("list assignment index out of range")
        self.values[node].items[index] = child

    def clone(mut self, node: Int) raises -> Int:
        """Copy a value and everything inside it, as `copy.deepcopy` does.

        Args:
            node: A value or `NOTHING`.

        Returns:
            The copy. `NOTHING` copies to a new `null`.

        Raises:
            Error: If `node` is not a value of the tree.
        """
        var kind = self.kind(node)
        if node == NOTHING:
            return self.null()
        var copy = self._add(kind)
        self.values[copy].integral = self.values[node].integral
        self.values[copy].number = self.values[node].number
        self.values[copy].integer = self.values[node].integer
        self.values[copy].text = self.values[node].text
        self.values[copy].names = self.values[node].names.copy()
        var count = len(self.values[node].items)
        for index in range(count):
            var original = self.values[node].items[index]
            var child = self.clone(original)
            self.values[copy].items.append(child)
        return copy

    def adopt(mut self, other: JsonTree, node: Int) raises -> Int:
        """Copy a value of another tree into this one.

        Args:
            other: The other tree.
            node: A value of `other`, or `NOTHING`.

        Returns:
            The copy in this tree.

        Raises:
            Error: If `node` is not a value of `other`.
        """
        var kind = other.kind(node)
        if node == NOTHING:
            return self.null()
        var copy = self._add(kind)
        self.values[copy].integral = other.values[node].integral
        self.values[copy].number = other.values[node].number
        self.values[copy].integer = other.values[node].integer
        self.values[copy].text = other.values[node].text
        self.values[copy].names = other.values[node].names.copy()
        for child in other.values[node].items:
            var item = self.adopt(other, child)
            self.values[copy].items.append(item)
        return copy

    # --- Python meanings ----------------------------------------------------

    def truthy(self, node: Int) raises -> Bool:
        """Return Python's truth value.

        Args:
            node: A value or `NOTHING`.

        Returns:
            False for `None`, `False`, zero and empty text, arrays and
            objects.

        Raises:
            Error: If `node` is not a value of the tree.
        """
        var kind = self.kind(node)
        if kind == NULL:
            return False
        if kind == BOOLEAN or kind == NUMBER:
            return self.value(node) != 0
        if kind == STRING:
            return self.values[node].text.byte_length() > 0
        return len(self.values[node].items) > 0

    def equal(self, a: Int, b: Int) raises -> Bool:
        """Return whether two values of this tree are equal under `==`.

        Args:
            a: A value or `NOTHING`.
            b: A value or `NOTHING`.

        Returns:
            True when they are equal.

        Raises:
            Error: If a value is not in the tree.
        """
        return equal(self, a, self, b)

    # --- text ---------------------------------------------------------------

    def parse(mut self, text: String) raises -> Int:
        """Read JSON text as `json.loads` does, and add its value.

        Args:
            text: The text.

        Returns:
            The value's index.

        Raises:
            Error: If the text is not one JSON value, in the form
                `json.loads` reports.
        """
        var reader = _Reader(text)
        reader.skip_space()
        var node = reader.value(self, 0)
        reader.skip_space()
        if not reader.done():
            raise Error(reader.where("Extra data"))
        return node

    def _float_text(mut self, value: Float64) raises -> String:
        """Return a float's `repr`, remembered by its bits."""
        var bits = bitcast[DType.uint64](value)
        var found = self.reprs.get(bits)
        if found:
            return found.value()
        var text = python_repr(value)
        self.reprs[bits] = text
        return text^

    def dumps(mut self, node: Int, indent: Bool = True) raises -> String:
        """Write a value as `json.dumps(value, indent=2, allow_nan=False)`
        does, or without `indent` in its compact default form.

        Args:
            node: A value or `NOTHING`.
            indent: True for `indent=2`; False for one line with `, ` and
                `: ` separators.

        Returns:
            The text, without a final newline.

        Raises:
            Error: For a float that is not finite, as `allow_nan=False`
                refuses it.
        """
        var out = String()
        self._write(out, node, 0, indent)
        return out^

    def _write(
        mut self, mut out: String, node: Int, depth: Int, indent: Bool
    ) raises:
        """Append one value's text."""
        var kind = self.kind(node)
        if kind == NULL:
            out += "null"
        elif kind == BOOLEAN:
            out += "true" if self.values[node].integer != 0 else "false"
        elif kind == NUMBER:
            if self.values[node].integral:
                out += String(self.values[node].integer)
            else:
                var number = self.values[node].number
                if isnan(number) or isinf(number):
                    raise Error(
                        "Out of range float values are not JSON compliant: "
                        + python_repr(number)
                    )
                out += self._float_text(number)
        elif kind == STRING:
            out += quote_ascii(self.values[node].text)
        else:
            var opener = "[" if kind == ARRAY else "{"
            var closer = "]" if kind == ARRAY else "}"
            var count = len(self.values[node].items)
            if count == 0:
                out += opener + closer
                return
            out += opener
            for index in range(count):
                if index > 0:
                    out += "," if indent else ", "
                if indent:
                    out += "\n" + "  " * (depth + 1)
                if kind == OBJECT:
                    out += quote_ascii(self.values[node].names[index]) + ": "
                var child = self.values[node].items[index]
                self._write(out, child, depth + 1, indent)
            if indent:
                out += "\n" + "  " * depth
            out += closer


def equal(left: JsonTree, a: Int, right: JsonTree, b: Int) raises -> Bool:
    """Return whether two values are equal under Python's `==`.

    Objects compare by their member sets, arrays by position. Numbers and
    Booleans compare by value, as `True == 1` does. A NaN equals nothing.

    Args:
        left: The first tree.
        a: A value of `left`, or `NOTHING`.
        right: The second tree.
        b: A value of `right`, or `NOTHING`.

    Returns:
        True when the values are equal.

    Raises:
        Error: If a value is not in its tree.
    """
    var ka = left.kind(a)
    var kb = right.kind(b)
    if ka == NULL or kb == NULL:
        return ka == kb
    if (ka == NUMBER or ka == BOOLEAN) and (kb == NUMBER or kb == BOOLEAN):
        if (ka != NUMBER or left.values[a].integral) and (
            kb != NUMBER or right.values[b].integral
        ):
            return left.values[a].integer == right.values[b].integer
        return left.value(a) == right.value(b)
    if ka != kb:
        return False
    if ka == STRING:
        return left.values[a].text == right.values[b].text
    var count = len(left.values[a].items)
    if count != len(right.values[b].items):
        return False
    if ka == ARRAY:
        for index in range(count):
            if not equal(
                left,
                left.values[a].items[index],
                right,
                right.values[b].items[index],
            ):
                return False
        return True
    for index in range(count):
        var other = right._find(b, left.values[a].names[index])
        if other < 0:
            return False
        if not equal(
            left,
            left.values[a].items[index],
            right,
            right.values[b].items[other],
        ):
            return False
    return True


def parse_number(text: String) raises -> Float64:
    """Return the double nearest to a decimal number, as `float()` does.

    A number of at most 15 digits with a small exponent is one exact
    division or product, which IEEE arithmetic rounds correctly. Any other
    number goes to the exact parser.

    Args:
        text: A JSON number.

    Returns:
        The nearest double.

    Raises:
        Error: If the text is not a number.
    """
    var bytes = text.as_bytes()
    var index = 0
    var negative = False
    if index < len(bytes) and bytes[index] == 45:
        negative = True
        index += 1
    var digits = 0
    var count = 0
    var exponent = 0
    var point = False
    while index < len(bytes):
        var byte = bytes[index]
        if byte >= 48 and byte <= 57:
            if count > 0 or byte != 48:
                count += 1
            if count > 15:
                return parse_float(text)
            digits = digits * 10 + Int(byte) - 48
            if point:
                exponent -= 1
        elif byte == 46 and not point:
            point = True
        else:
            break
        index += 1
    if index < len(bytes):
        if bytes[index] != 101 and bytes[index] != 69:
            return parse_float(text)
        var tail = bytes[index + 1 :]
        var sign = 1
        var start = 0
        if len(tail) > 0 and (tail[0] == 43 or tail[0] == 45):
            sign = -1 if tail[0] == 45 else 1
            start = 1
        if len(tail) - start > 4 or len(tail) - start < 1:
            return parse_float(text)
        var power = 0
        for position in range(start, len(tail)):
            if tail[position] < 48 or tail[position] > 57:
                return parse_float(text)
            power = power * 10 + Int(tail[position]) - 48
        exponent += sign * power
    var value = Float64(digits)
    var powers = materialize[_POWERS]()
    if exponent < -22 or exponent > 22:
        return parse_float(text)
    if exponent < 0:
        value = value / powers[-exponent]
    else:
        value = value * powers[exponent]
    return -value if negative else value


struct _Reader(Movable):
    """A position in JSON text."""

    var text: String
    var position: Int

    def __init__(out self, text: String):
        self.text = text
        self.position = 0

    def done(self) -> Bool:
        return self.position >= self.text.byte_length()

    def peek(self) -> Int:
        if self.done():
            return -1
        return Int(self.text.as_bytes()[self.position])

    def where(self, message: String) -> String:
        """Return a message with Python's line, column and offset."""
        var bytes = self.text.as_bytes()
        var line = 1
        var column = 1
        var offset = 0
        for index in range(min(self.position, len(bytes))):
            var byte = bytes[index]
            if (byte & 0xC0) == 0x80:
                continue
            offset += 1
            if byte == 10:
                line += 1
                column = 1
            else:
                column += 1
        return (
            message
            + ": line "
            + String(line)
            + " column "
            + String(column)
            + " (char "
            + String(offset)
            + ")"
        )

    def skip_space(mut self):
        var bytes = self.text.as_bytes()
        while self.position < len(bytes):
            var byte = bytes[self.position]
            if byte == 32 or byte == 9 or byte == 10 or byte == 13:
                self.position += 1
            else:
                return

    def starts(self, word: String) -> Bool:
        """Return whether the text goes on with a word."""
        var end = self.position + word.byte_length()
        return (
            end <= self.text.byte_length()
            and String(self.text[byte = self.position : end]) == word
        )

    def value(mut self, mut tree: JsonTree, depth: Int) raises -> Int:
        if depth > MAX_DEPTH:
            raise Error("maximum recursion depth exceeded")
        var byte = self.peek()
        if byte == 34:
            return tree.string(self.string())
        if byte == 123:
            return self.object(tree, depth)
        if byte == 91:
            return self.array(tree, depth)
        if byte == 110 and self.starts("null"):
            self.position += 4
            return tree.null()
        if byte == 116 and self.starts("true"):
            self.position += 4
            return tree.boolean(True)
        if byte == 102 and self.starts("false"):
            self.position += 5
            return tree.boolean(False)
        if byte == 78 and self.starts("NaN"):
            self.position += 3
            return tree.number(parse_float("nan"))
        if byte == 73 and self.starts("Infinity"):
            self.position += 8
            return tree.number(parse_float("inf"))
        if byte == 45 and self.starts("-Infinity"):
            self.position += 9
            return tree.number(parse_float("-inf"))
        if byte == 45 or (byte >= 48 and byte <= 57):
            return self.number(tree)
        raise Error(self.where("Expecting value"))

    def number(mut self, mut tree: JsonTree) raises -> Int:
        var bytes = self.text.as_bytes()
        var start = self.position
        var index = start
        if bytes[index] == 45:
            index += 1
        if index >= len(bytes) or bytes[index] < 48 or bytes[index] > 57:
            raise Error(self.where("Expecting value"))
        if bytes[index] == 48:
            index += 1
        else:
            while (
                index < len(bytes) and bytes[index] >= 48 and bytes[index] <= 57
            ):
                index += 1
        var integral = True
        if (
            index + 1 < len(bytes)
            and bytes[index] == 46
            and bytes[index + 1] >= 48
            and bytes[index + 1] <= 57
        ):
            integral = False
            index += 1
            while (
                index < len(bytes) and bytes[index] >= 48 and bytes[index] <= 57
            ):
                index += 1
        if index < len(bytes) and (bytes[index] == 101 or bytes[index] == 69):
            var probe = index + 1
            if probe < len(bytes) and (
                bytes[probe] == 43 or bytes[probe] == 45
            ):
                probe += 1
            if probe < len(bytes) and bytes[probe] >= 48 and bytes[probe] <= 57:
                integral = False
                index = probe
                while (
                    index < len(bytes)
                    and bytes[index] >= 48
                    and bytes[index] <= 57
                ):
                    index += 1
        var token = String(self.text[byte=start:index])
        self.position = index
        if integral:
            if token.byte_length() > 18:
                raise Error("integer too large for this tool: " + token)
            return tree.integer(Int(token))
        return tree.number(parse_number(token))

    def string(mut self) raises -> String:
        var bytes = self.text.as_bytes()
        var begin = self.position
        self.position += 1
        var out = String()
        var start = self.position
        while True:
            if self.position >= len(bytes):
                self.position = begin
                raise Error(self.where("Unterminated string starting at"))
            var byte = bytes[self.position]
            if byte == 34:
                out += String(self.text[byte = start : self.position])
                self.position += 1
                return out^
            if byte < 32:
                raise Error(self.where("Invalid control character at"))
            if byte != 92:
                self.position += 1
                continue
            out += String(self.text[byte = start : self.position])
            if self.position + 1 >= len(bytes):
                self.position = begin
                raise Error(self.where("Unterminated string starting at"))
            var letter = bytes[self.position + 1]
            self.position += 2
            if letter == 34:
                out += '"'
            elif letter == 92:
                out += "\\"
            elif letter == 47:
                out += "/"
            elif letter == 98:
                out += "\x08"
            elif letter == 102:
                out += "\x0c"
            elif letter == 110:
                out += "\n"
            elif letter == 114:
                out += "\r"
            elif letter == 116:
                out += "\t"
            elif letter == 117:
                var unit = self.unit(self.position)
                self.position += 4
                if unit >= 0xD800 and unit <= 0xDBFF:
                    if (
                        self.position + 1 < len(bytes)
                        and bytes[self.position] == 92
                        and bytes[self.position + 1] == 117
                    ):
                        var low = self.unit(self.position + 2)
                        if low >= 0xDC00 and low <= 0xDFFF:
                            self.position += 6
                            unit = (
                                0x10000
                                + ((unit - 0xD800) << 10)
                                + (low - 0xDC00)
                            )
                        else:
                            unit = 0xFFFD
                    else:
                        unit = 0xFFFD
                elif unit >= 0xDC00 and unit <= 0xDFFF:
                    unit = 0xFFFD
                out += chr(unit)
            else:
                self.position -= 2
                raise Error(self.where("Invalid \\escape"))
            start = self.position

    def unit(self, position: Int) raises -> Int:
        """Read four hexadecimal digits at a position."""
        var bytes = self.text.as_bytes()
        var value = 0
        for offset in range(4):
            if position + offset >= len(bytes):
                raise Error(self.where("Invalid \\uXXXX escape"))
            var byte = Int(bytes[position + offset])
            var digit: Int
            if byte >= 48 and byte <= 57:
                digit = byte - 48
            elif byte >= 97 and byte <= 102:
                digit = byte - 87
            elif byte >= 65 and byte <= 70:
                digit = byte - 55
            else:
                raise Error(self.where("Invalid \\uXXXX escape"))
            value = value * 16 + digit
        return value

    def object(mut self, mut tree: JsonTree, depth: Int) raises -> Int:
        var node = tree.object()
        self.position += 1
        self.skip_space()
        if self.peek() == 125:
            self.position += 1
            return node
        while True:
            if self.peek() != 34:
                raise Error(
                    self.where(
                        "Expecting property name enclosed in double quotes"
                    )
                )
            var key = self.string()
            self.skip_space()
            if self.peek() != 58:
                raise Error(self.where("Expecting ':' delimiter"))
            self.position += 1
            self.skip_space()
            var child = self.value(tree, depth + 1)
            tree.set(node, key, child)
            self.skip_space()
            var byte = self.peek()
            if byte == 125:
                self.position += 1
                return node
            if byte != 44:
                raise Error(self.where("Expecting ',' delimiter"))
            self.position += 1
            self.skip_space()

    def array(mut self, mut tree: JsonTree, depth: Int) raises -> Int:
        var node = tree.array()
        self.position += 1
        self.skip_space()
        if self.peek() == 93:
            self.position += 1
            return node
        while True:
            var child = self.value(tree, depth + 1)
            tree.values[node].items.append(child)
            self.skip_space()
            var byte = self.peek()
            if byte == 93:
                self.position += 1
                return node
            if byte != 44:
                raise Error(self.where("Expecting ',' delimiter"))
            self.position += 1
            self.skip_space()
