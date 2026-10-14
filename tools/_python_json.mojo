# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Python values read from JSON and written back with CPython 3.12's rules.

A tool that replaces a Python JSON tool must keep Python behaviors that
`loaders.json` does not keep:

- An `int` and a `float` stay apart. An int keeps all of its digits, and a
  float writes as `repr` writes it.
- `loads` is `json.loads` on bytes. It detects UTF-8, UTF-16 and UTF-32 as
  Python does, and it raises Python's error text, with the line, the
  column and the character offset.
- `dumps_canonical` is `json.dumps(value, sort_keys=True,
  separators=(",", ":"), ensure_ascii=True, allow_nan=False)`. It refuses
  a value that is not finite with Python's text.
- `py_equal` is Python's `==`: `1 == 1.0` and `True == 1`.

`PyJson` holds one tree of values in a flat list of nodes. A node is an
index into that list. A string is held as UTF-8 bytes, and a lone surrogate
from an escape or from the input keeps its three-byte form, as Python's
`surrogatepass` decoder gives it.

An error that Python raises as `ValueError` has Python's text. An error
that the Python tool does not catch starts with the exception name, such
as `OverflowError: ` or `RecursionError: `.
"""

from std.math import isinf, isnan

from tools._bigint import BigInt
from tools._fraction import Fraction
from tools._python_float import parse_float, python_repr


@fieldwise_init
struct PyKind(Equatable, ImplicitlyCopyable, Writable):
    """What a Python value is: `None`, a bool, an int, a float, a str, a
    list or a dict."""

    var value: Int
    """The kind number."""

    def is_valid(self) -> Bool:
        """Return whether this is one of the seven kinds.

        Returns:
            True for a kind that `PyJson` can hold.
        """
        return self.value >= 0 and self.value <= 6


comptime PY_NONE = PyKind(0)
"""Python's `None`, JSON's `null`."""
comptime PY_BOOL = PyKind(1)
"""A bool."""
comptime PY_INT = PyKind(2)
"""An int, with all of its digits."""
comptime PY_FLOAT = PyKind(3)
"""A float."""
comptime PY_STR = PyKind(4)
"""A str."""
comptime PY_LIST = PyKind(5)
"""A list."""
comptime PY_DICT = PyKind(6)
"""A dict, in insertion order."""

comptime MISSING = -1
"""The node of an absent value, as `dict.get` gives `None`."""
comptime MAX_DEPTH = 9997
"""The deepest nesting that CPython 3.12 reads or writes in a tool's main
module. One more level raises `RecursionError`."""
comptime OVERFLOW = "OverflowError: "
"""The start of an `OverflowError` text."""
comptime RECURSION = "RecursionError: "
"""The start of a `RecursionError` text."""
comptime INT_DIGITS = 4300
"""Python's limit on the digits of an int read from text."""

comptime _HEX = "0123456789abcdef"


struct _Node(Copyable, Movable):
    """One value. Its kind says which fields it uses."""

    var kind: PyKind
    var flag: Bool
    var number: Float64
    # A str's bytes, an int's digits, or a float's `repr`.
    var text: String
    # A list's items or a dict's values.
    var items: List[Int]
    # A dict's keys, one per value.
    var keys: List[String]

    def __init__(out self, kind: PyKind):
        self.kind = kind
        self.flag = False
        self.number = 0.0
        self.text = String()
        self.items = List[Int]()
        self.keys = List[String]()

    def shallow(self) -> _Node:
        """Copy the node with each child slot set to `MISSING`."""
        var out = _Node(self.kind)
        out.flag = self.flag
        out.number = self.number
        out.text = self.text
        out.keys = self.keys.copy()
        out.items = List[Int](length=len(self.items), fill=MISSING)
        return out^


struct PyJson(Copyable, Movable):
    """A tree of Python values held as a flat list of nodes."""

    var nodes: List[_Node]
    """Every node. A replaced value stays in the list, unreferenced."""
    var root: Int
    """The node of the whole value."""

    def __init__(out self):
        """Make a document whose root is `None`."""
        self.nodes = List[_Node]()
        self.nodes.append(_Node(PY_NONE))
        self.root = 0

    @staticmethod
    def parse(text: String) raises -> PyJson:
        """Read JSON text, as `json.loads` does.

        Args:
            text: The JSON text.

        Returns:
            The document.

        Raises:
            Error: With Python's text, if the text is not JSON.
        """
        return loads(text.as_bytes())

    def _add(mut self, var node: _Node) -> Int:
        self.nodes.append(node^)
        return len(self.nodes) - 1

    def new_none(mut self) -> Int:
        """Add `None`.

        Returns:
            The new node.
        """
        return self._add(_Node(PY_NONE))

    def new_bool(mut self, value: Bool) -> Int:
        """Add a bool.

        Args:
            value: The bool.

        Returns:
            The new node.
        """
        var node = _Node(PY_BOOL)
        node.flag = value
        return self._add(node^)

    def new_int(mut self, value: Int) -> Int:
        """Add an int.

        Args:
            value: The int.

        Returns:
            The new node.
        """
        var node = _Node(PY_INT)
        node.text = String(value)
        return self._add(node^)

    def new_float(mut self, value: Float64) raises -> Int:
        """Add a float.

        Args:
            value: The float.

        Returns:
            The new node.

        Raises:
            Error: Never; it signals an internal failure of `repr`.
        """
        var node = _Node(PY_FLOAT)
        node.number = value
        node.text = python_repr(value)
        return self._add(node^)

    def new_str(mut self, text: String) -> Int:
        """Add a str.

        Args:
            text: The UTF-8 bytes.

        Returns:
            The new node.
        """
        var node = _Node(PY_STR)
        node.text = text
        return self._add(node^)

    def new_list(mut self) -> Int:
        """Add an empty list.

        Returns:
            The new node.
        """
        return self._add(_Node(PY_LIST))

    def new_dict(mut self) -> Int:
        """Add an empty dict.

        Returns:
            The new node.
        """
        return self._add(_Node(PY_DICT))

    def kind(self, node: Int) -> PyKind:
        """Return a node's kind; `MISSING` is `None`.

        Args:
            node: The node, or `MISSING`.

        Returns:
            The kind.
        """
        if node == MISSING:
            return PY_NONE
        return self.nodes[node].kind

    def is_none(self, node: Int) -> Bool:
        """Return whether a value is `None`.

        Args:
            node: The node, or `MISSING`.

        Returns:
            True for `None` and for `MISSING`.
        """
        return self.kind(node) == PY_NONE

    def length(self, node: Int) -> Int:
        """Return the number of items of a list or a dict.

        Args:
            node: A list or a dict.

        Returns:
            The number of items.
        """
        return len(self.nodes[node].items)

    def item(self, node: Int, index: Int) raises -> Int:
        """Return a list item, as `list[index]` does for a nonnegative index.

        Args:
            node: A list.
            index: The position.

        Returns:
            The item's node.

        Raises:
            Error: If the position is past the end.
        """
        if index < 0 or index >= len(self.nodes[node].items):
            raise Error("IndexError: list index out of range")
        return self.nodes[node].items[index]

    def key(self, node: Int, index: Int) -> String:
        """Return the key at a dict position.

        Args:
            node: A dict.
            index: The position, in insertion order.

        Returns:
            The key.
        """
        return self.nodes[node].keys[index]

    def value(self, node: Int, index: Int) -> Int:
        """Return the value at a dict position.

        Args:
            node: A dict.
            index: The position, in insertion order.

        Returns:
            The value's node.
        """
        return self.nodes[node].items[index]

    def find(self, node: Int, key: String) -> Int:
        """Return a dict's value for a key, or `MISSING`.

        Args:
            node: A dict.
            key: The key.

        Returns:
            The value's node, or `MISSING`.
        """
        ref keys = self.nodes[node].keys
        for index in range(len(keys)):
            if keys[index] == key:
                return self.nodes[node].items[index]
        return MISSING

    def get(self, node: Int, key: String) -> Int:
        """Return a member as `dict.get` does.

        Args:
            node: A node; a value that is not a dict has no members.
            key: The key.

        Returns:
            The value's node, or `MISSING`.
        """
        if node == MISSING or self.nodes[node].kind != PY_DICT:
            return MISSING
        return self.find(node, key)

    def at(self, node: Int, key: String) raises -> Int:
        """Return a member as `dict[key]` does.

        Args:
            node: A dict.
            key: The key.

        Returns:
            The value's node.

        Raises:
            Error: With Python's `KeyError` text if the key is absent.
        """
        var found = self.get(node, key)
        if found == MISSING:
            raise Error("KeyError: " + py_repr(key))
        return found

    def text(self, node: Int) -> String:
        """Return a str's bytes, an int's digits or a float's `repr`.

        Args:
            node: The node.

        Returns:
            The text.
        """
        return self.nodes[node].text

    def number(self, node: Int) -> Float64:
        """Return a float's value.

        Args:
            node: A float.

        Returns:
            The value.
        """
        return self.nodes[node].number

    def flag(self, node: Int) -> Bool:
        """Return a bool's value.

        Args:
            node: A bool.

        Returns:
            The value.
        """
        return self.nodes[node].flag

    def set(mut self, node: Int, key: String, value: Int):
        """Set a dict member, as `dict[key] = value` does.

        An existing key keeps its position.

        Args:
            node: A dict.
            key: The key.
            value: The value's node.
        """
        ref keys = self.nodes[node].keys
        for index in range(len(keys)):
            if keys[index] == key:
                self.nodes[node].items[index] = value
                return
        self.nodes[node].keys.append(key)
        self.nodes[node].items.append(value)

    def remove(mut self, node: Int, key: String) raises:
        """Delete a dict member, as `del dict[key]` does.

        Args:
            node: A dict.
            key: The key.

        Raises:
            Error: With Python's `KeyError` text if the key is absent.
        """
        var keys = self.nodes[node].keys.copy()
        for index in range(len(keys)):
            if keys[index] == key:
                _ = self.nodes[node].keys.pop(index)
                _ = self.nodes[node].items.pop(index)
                return
        raise Error("KeyError: " + py_repr(key))

    def append(mut self, node: Int, value: Int):
        """Append a list item.

        Args:
            node: A list.
            value: The item's node.
        """
        self.nodes[node].items.append(value)

    def set_item(mut self, node: Int, index: Int, value: Int) raises:
        """Replace a list item, as `list[index] = value` does.

        Args:
            node: A list.
            index: The nonnegative position.
            value: The item's node.

        Raises:
            Error: If the position is past the end.
        """
        if index < 0 or index >= len(self.nodes[node].items):
            raise Error("IndexError: list assignment index out of range")
        self.nodes[node].items[index] = value

    def copy_node(mut self, node: Int) -> Int:
        """Copy a value and everything in it, as `copy.deepcopy` does.

        Args:
            node: The value.

        Returns:
            The copy's node.
        """
        var top = self._add(self.nodes[node].shallow())
        var pending: List[Tuple[Int, Int]] = [(node, top)]
        while len(pending) > 0:
            var pair = pending.pop()
            for slot in range(len(self.nodes[pair[0]].items)):
                var child = self.nodes[pair[0]].items[slot]
                var made = self._add(self.nodes[child].shallow())
                self.nodes[pair[1]].items[slot] = made
                pending.append((child, made))
        return top

    def adopt(mut self, other: PyJson, node: Int) -> Int:
        """Copy a value of another document into this one.

        Args:
            other: The other document.
            node: The value in `other`.

        Returns:
            The copy's node in this document.
        """
        var top = self._add(other.nodes[node].shallow())
        var pending: List[Tuple[Int, Int]] = [(node, top)]
        while len(pending) > 0:
            var pair = pending.pop()
            for slot in range(len(other.nodes[pair[0]].items)):
                var child = other.nodes[pair[0]].items[slot]
                var made = self._add(other.nodes[child].shallow())
                self.nodes[pair[1]].items[slot] = made
                pending.append((child, made))
        return top

    def subtree(self, node: Int) -> PyJson:
        """Return a value as a document of its own.

        Args:
            node: The value.

        Returns:
            A deep copy whose root is the value.
        """
        var out = PyJson()
        out.root = out.adopt(self, node)
        return out^

    def dumps(self) raises -> String:
        """Return the canonical JSON text of the root value.

        Returns:
            The text, as `dumps_canonical` writes it.

        Raises:
            Error: With Python's text for a value that is not finite.
        """
        return dumps_canonical(self, self.root)


# --- Python's str rules ----------------------------------------------------------


def _append_point(mut out: List[UInt8], point: Int):
    """Append one code point, a lone surrogate included, as UTF-8."""
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


def _continuation(byte: UInt8) -> Bool:
    """Return whether a byte continues a UTF-8 sequence."""
    return byte >= 0x80 and byte <= 0xBF


def _utf8_step(data: Span[UInt8, _], at: Int, end: Int) -> Tuple[Int, Int]:
    """Classify the UTF-8 sequence at a position as CPython's decoder does.

    Returns:
        (length, code) for a valid sequence, where code is the code point.
        Otherwise (-kind, length): kind 0 is an unexpected end of data
        through `end`, kind 1 an invalid start byte, and kind 2 an invalid
        continuation byte; length is the number of bytes in error.
    """
    var c = Int(data[at])
    if c < 0x80:
        return (1, c)
    if c < 0xC2:
        return (-1, 1)
    if c < 0xE0:
        if end - at < 2:
            return (0, end - at)
        if not _continuation(data[at + 1]):
            return (-2, 1)
        return (2, ((c & 0x1F) << 6) | (Int(data[at + 1]) & 0x3F))
    if c < 0xF0:
        if end - at < 3:
            if end - at < 2:
                return (0, end - at)
            var c2 = Int(data[at + 1])
            if not _continuation(data[at + 1]) or (
                c == 0xE0 if c2 < 0xA0 else c == 0xED
            ):
                return (-2, 1)
            return (0, end - at)
        var c2 = Int(data[at + 1])
        if not _continuation(data[at + 1]):
            return (-2, 1)
        if (c == 0xE0 and c2 < 0xA0) or (c == 0xED and c2 >= 0xA0):
            return (-2, 1)
        if not _continuation(data[at + 2]):
            return (-2, 2)
        return (
            3,
            ((c & 0x0F) << 12)
            | ((c2 & 0x3F) << 6)
            | (Int(data[at + 2]) & 0x3F),
        )
    if c < 0xF5:
        if end - at < 4:
            if end - at < 2:
                return (0, end - at)
            var c2 = Int(data[at + 1])
            if not _continuation(data[at + 1]) or (
                c == 0xF0 if c2 < 0x90 else c == 0xF4
            ):
                return (-2, 1)
            if end - at < 3:
                return (0, end - at)
            if not _continuation(data[at + 2]):
                return (-2, 2)
            return (0, end - at)
        var c2 = Int(data[at + 1])
        if not _continuation(data[at + 1]):
            return (-2, 1)
        if (c == 0xF0 and c2 < 0x90) or (c == 0xF4 and c2 >= 0x90):
            return (-2, 1)
        if not _continuation(data[at + 2]):
            return (-2, 2)
        if not _continuation(data[at + 3]):
            return (-2, 3)
        return (
            4,
            ((c & 0x07) << 18)
            | ((c2 & 0x3F) << 12)
            | ((Int(data[at + 2]) & 0x3F) << 6)
            | (Int(data[at + 3]) & 0x3F),
        )
    return (-1, 1)


def _surrogate_at(data: Span[UInt8, _], at: Int, end: Int) -> Int:
    """Return the surrogate that three bytes encode, or -1, as Python's
    `surrogatepass` handler reads them."""
    if end - at < 3:
        return -1
    var c = Int(data[at])
    if (
        (c & 0xF0) != 0xE0
        or not _continuation(data[at + 1])
        or not _continuation(data[at + 2])
    ):
        return -1
    var point = (
        ((c & 0x0F) << 12)
        | ((Int(data[at + 1]) & 0x3F) << 6)
        | (Int(data[at + 2]) & 0x3F)
    )
    if point >= 0xD800 and point <= 0xDFFF:
        return point
    return -1


def _decode_error(
    encoding: String,
    data: Span[UInt8, _],
    start: Int,
    stop: Int,
    reason: String,
    base: Int,
) -> String:
    """Return a `UnicodeDecodeError` text for the bytes [start, stop)."""
    var head = "'" + encoding + "' codec can't decode "
    if stop - start == 1:
        return (
            head
            + "byte 0x"
            + _hex_byte(Int(data[start]))
            + " in position "
            + String(start - base)
            + ": "
            + reason
        )
    return (
        head
        + "bytes in position "
        + String(start - base)
        + "-"
        + String(stop - 1 - base)
        + ": "
        + reason
    )


def _hex_byte(value: Int) -> String:
    """Return two lowercase hexadecimal digits."""
    var out = String()
    out += chr(Int(_HEX.as_bytes()[(value >> 4) & 15]))
    out += chr(Int(_HEX.as_bytes()[value & 15]))
    return out^


def code_points(text: String, escape_invalid: Bool) -> List[Int]:
    """Return a str's code points.

    Args:
        text: The bytes.
        escape_invalid: True to read the bytes as Python reads a command
            line, with `surrogateescape`: each byte of an invalid sequence,
            an encoded surrogate included, becomes U+DC80 to U+DCFF. False
            to read a lone surrogate's three bytes as the surrogate.

    Returns:
        The code points.
    """
    var data = text.as_bytes()
    var out = List[Int]()
    var at = 0
    while at < len(data):
        var step = _utf8_step(data, at, len(data))
        if step[0] > 0:
            out.append(step[1])
            at += step[0]
            continue
        if not escape_invalid:
            var surrogate = _surrogate_at(data, at, len(data))
            if surrogate >= 0:
                out.append(surrogate)
                at += 3
                continue
        var count = step[1] if step[0] != -1 else 1
        for index in range(count):
            out.append(0xDC00 + Int(data[at + index]))
        at += count
    return out^


def is_space(point: Int) -> Bool:
    """Return whether a code point is whitespace, as `str.isspace` says.

    Args:
        point: The code point.

    Returns:
        True for the characters that `str.strip` removes.
    """
    return (
        (point >= 0x09 and point <= 0x0D)
        or (point >= 0x1C and point <= 0x20)
        or point == 0x85
        or point == 0xA0
        or point == 0x1680
        or (point >= 0x2000 and point <= 0x200A)
        or point == 0x2028
        or point == 0x2029
        or point == 0x202F
        or point == 0x205F
        or point == 0x3000
    )


def is_blank(text: String) -> Bool:
    """Return whether `text.strip()` is empty.

    Args:
        text: The str's bytes.

    Returns:
        True when every character is whitespace.
    """
    for point in code_points(text, False):
        if not is_space(point):
            return False
    return True


def _printable(point: Int) -> Bool:
    """Return whether `repr` shows a code point as itself.

    The set is Python's for ASCII, Latin-1, spaces, separators, format
    characters, surrogates and private use. Other unassigned characters
    count as printable.
    """
    if point < 0x20 or (point >= 0x7F and point <= 0xA0):
        return False
    if point == 0xAD or (point != 0x20 and is_space(point)):
        return False
    if point >= 0x600 and point <= 0x605:
        return False
    if (
        point == 0x61C
        or point == 0x6DD
        or point == 0x70F
        or point == 0x890
        or point == 0x891
        or point == 0x8E2
        or point == 0x180E
        or point == 0xFEFF
    ):
        return False
    if (point >= 0x200B and point <= 0x200F) or (
        point >= 0x202A and point <= 0x202E
    ):
        return False
    if point >= 0x2060 and point <= 0x206F:
        return False
    if point >= 0xD800 and point <= 0xF8FF:
        return False
    if (
        (point >= 0xFFF0 and point <= 0xFFFB)
        or point == 0xFFFE
        or (point == 0xFFFF)
    ):
        return False
    if point >= 0xE0000:
        return False
    return True


def py_repr(text: String) -> String:
    """Return `repr(text)` as Python writes it.

    The bytes are read as Python reads a command line or a file name, with
    `surrogateescape`.

    Args:
        text: The str's bytes.

    Returns:
        The quoted text with Python's escapes.
    """
    var points = code_points(text, True)
    var quote = 0x27
    var single = False
    var double = False
    for point in points:
        if point == 0x27:
            single = True
        elif point == 0x22:
            double = True
    if single and not double:
        quote = 0x22
    var out = List[UInt8]()
    out.append(UInt8(quote))
    for point in points:
        if point == quote or point == 0x5C:
            out.append(0x5C)
            out.append(UInt8(point))
        elif point == 0x09:
            out.append(0x5C)
            out.append(0x74)
        elif point == 0x0A:
            out.append(0x5C)
            out.append(0x6E)
        elif point == 0x0D:
            out.append(0x5C)
            out.append(0x72)
        elif _printable(point):
            _append_point(out, point)
        else:
            var digits: Int
            out.append(0x5C)
            if point < 0x100:
                out.append(0x78)
                digits = 2
            elif point < 0x10000:
                out.append(0x75)
                digits = 4
            else:
                out.append(0x55)
                digits = 8
            for place in range(digits - 1, -1, -1):
                out.append(_HEX.as_bytes()[(point >> (4 * place)) & 15])
    out.append(UInt8(quote))
    return String(unsafe_from_utf8=out)


# --- Decoding bytes ----------------------------------------------------------------


def _check_utf8(data: Span[UInt8, _], begin: Int) raises:
    """Refuse invalid UTF-8, as `bytes.decode("utf-8", "surrogatepass")`
    does; positions count from `begin`."""
    var at = begin
    var end = len(data)
    while at < end:
        if data[at] < 0x80:
            at += 1
            continue
        var step = _utf8_step(data, at, end)
        if step[0] > 0:
            at += step[0]
            continue
        if step[0] == -2 and step[1] == 1:
            if _surrogate_at(data, at, end) >= 0:
                at += 3
                continue
        var reason: String
        var stop: Int
        if step[0] == 0:
            reason = "unexpected end of data"
            stop = end
        elif step[0] == -1:
            reason = "invalid start byte"
            stop = at + 1
        else:
            reason = "invalid continuation byte"
            stop = at + step[1]
        raise Error(_decode_error("utf-8", data, at, stop, reason, begin))


def _decode_wide(
    data: Span[UInt8, _], begin: Int, width: Int, little: Bool
) raises -> List[UInt8]:
    """Decode UTF-16 or UTF-32 with `surrogatepass` into UTF-8 bytes."""
    var name = String("utf-16-" if width == 2 else "utf-32-") + (
        "le" if little else "be"
    )
    var out = List[UInt8]()
    var at = begin
    var end = len(data)
    var high = -1
    while at < end:
        if end - at < width:
            raise Error(_decode_error(name, data, at, end, "truncated data", 0))
        var unit = 0
        for index in range(width):
            var byte = Int(data[at + index])
            if little:
                unit |= byte << (8 * index)
            else:
                unit = (unit << 8) | byte
        if width == 4 and unit > 0x10FFFF:
            raise Error(
                _decode_error(
                    name,
                    data,
                    at,
                    at + 4,
                    "code point not in range(0x110000)",
                    0,
                )
            )
        at += width
        if width == 2:
            if high >= 0:
                if unit >= 0xDC00 and unit <= 0xDFFF:
                    _append_point(
                        out, 0x10000 + ((high - 0xD800) << 10) + (unit - 0xDC00)
                    )
                    high = -1
                    continue
                _append_point(out, high)
                high = -1
            if unit >= 0xD800 and unit <= 0xDBFF:
                high = unit
                continue
        _append_point(out, unit)
    if high >= 0:
        _append_point(out, high)
    return out^


# --- Reading JSON --------------------------------------------------------------------


def loads(data: Span[UInt8, _]) raises -> PyJson:
    """Read JSON bytes, as `json.loads(data)` does.

    Args:
        data: The bytes, in UTF-8, UTF-16 or UTF-32 as Python detects them.

    Returns:
        The document.

    Raises:
        Error: With Python's `JSONDecodeError`, `UnicodeDecodeError` or
            `ValueError` text, or a `RecursionError: ` text for a value
            nested past `MAX_DEPTH`.
    """
    var n = len(data)
    if n >= 4 and (
        (data[0] == 0 and data[1] == 0 and data[2] == 0xFE and data[3] == 0xFF)
        or (
            data[0] == 0xFF
            and data[1] == 0xFE
            and data[2] == 0
            and data[3] == 0
        )
    ):
        var wide = _decode_wide(data, 4, 4, data[0] == 0xFF)
        return _scan(wide, 0)
    if n >= 2 and (
        (data[0] == 0xFE and data[1] == 0xFF)
        or (data[0] == 0xFF and data[1] == 0xFE)
    ):
        var wide = _decode_wide(data, 2, 2, data[0] == 0xFF)
        return _scan(wide, 0)
    if n >= 3 and data[0] == 0xEF and data[1] == 0xBB and data[2] == 0xBF:
        _check_utf8(data, 3)
        return _scan(data, 3)
    if n >= 4:
        if data[0] == 0:
            var wide = _decode_wide(data, 0, 2 if data[1] != 0 else 4, False)
            return _scan(wide, 0)
        if data[1] == 0:
            var wide = _decode_wide(
                data, 0, 2 if data[2] != 0 or data[3] != 0 else 4, True
            )
            return _scan(wide, 0)
    elif n == 2:
        if data[0] == 0:
            var wide = _decode_wide(data, 0, 2, False)
            return _scan(wide, 0)
        if data[1] == 0:
            var wide = _decode_wide(data, 0, 2, True)
            return _scan(wide, 0)
    _check_utf8(data, 0)
    return _scan(data, 0)


def _position(data: Span[UInt8, _], begin: Int, at: Int) -> String:
    """Return `line L column C (char P)` for a byte offset, in characters."""
    var chars = 0
    var line = 1
    var last = -1
    for index in range(begin, min(at, len(data))):
        var byte = data[index]
        if not _continuation(byte):
            if byte == 0x0A:
                line += 1
                last = chars
            chars += 1
    if at > len(data):
        chars += at - len(data)
    return (
        "line "
        + String(line)
        + " column "
        + String(chars - last)
        + " (char "
        + String(chars)
        + ")"
    )


def _fail(data: Span[UInt8, _], begin: Int, message: String, at: Int) -> Error:
    """Return a `JSONDecodeError` text at a byte offset."""
    return Error(message + ": " + _position(data, begin, at))


def _is_space(byte: UInt8) -> Bool:
    """Return whether a byte is JSON whitespace."""
    return byte == 0x20 or byte == 0x09 or byte == 0x0A or byte == 0x0D


def _skip(data: Span[UInt8, _], at: Int) -> Int:
    """Return the first offset at or after `at` that is not whitespace."""
    var index = at
    while index < len(data) and _is_space(data[index]):
        index += 1
    return index


def _hex_value(byte: UInt8) -> Int:
    """Return a hexadecimal digit's value, or -1."""
    if byte >= 48 and byte <= 57:
        return Int(byte) - 48
    if byte >= 97 and byte <= 102:
        return Int(byte) - 87
    if byte >= 65 and byte <= 70:
        return Int(byte) - 55
    return -1


def _chars_from(data: Span[UInt8, _], at: Int, limit: Int) -> Int:
    """Return how many characters start at or after `at`, up to `limit`."""
    var count = 0
    var index = at
    while index < len(data) and count < limit:
        if not _continuation(data[index]):
            count += 1
        index += 1
    return count


def _four_hex(data: Span[UInt8, _], at: Int) -> Int:
    """Return the value of four hexadecimal digits at `at`, or -1."""
    if at + 4 > len(data):
        return -1
    var value = 0
    for index in range(4):
        var digit = _hex_value(data[at + index])
        if digit < 0:
            return -1
        value = value * 16 + digit
    return value


def _scan_string(
    data: Span[UInt8, _], begin: Int, start: Int
) raises -> Tuple[String, Int]:
    """Read a str after its opening quote, as CPython's scanner does.

    Returns:
        The bytes and the offset after the closing quote.
    """
    var out = List[UInt8]()
    var end = start
    var n = len(data)
    while True:
        var next = end
        var found = -1
        while next < n:
            var d = data[next]
            if d == 0x22 or d == 0x5C:
                found = Int(d)
                break
            if d <= 0x1F:
                raise _fail(data, begin, "Invalid control character at", next)
            next += 1
        if found < 0:
            raise _fail(
                data, begin, "Unterminated string starting at", start - 1
            )
        for index in range(end, next):
            out.append(data[index])
        next += 1
        if found == 0x22:
            return (String(unsafe_from_utf8=out), next)
        if next == n:
            raise _fail(
                data, begin, "Unterminated string starting at", start - 1
            )
        var c = data[next]
        if c != 0x75:
            end = next + 1
            if c == 0x22 or c == 0x5C or c == 0x2F:
                out.append(c)
            elif c == 0x62:
                out.append(0x08)
            elif c == 0x66:
                out.append(0x0C)
            elif c == 0x6E:
                out.append(0x0A)
            elif c == 0x72:
                out.append(0x0D)
            elif c == 0x74:
                out.append(0x09)
            else:
                raise _fail(data, begin, "Invalid \\escape", end - 2)
            continue
        # A \uXXXX escape: `next` is at the u.
        var first = next + 1
        if _chars_from(data, first, 5) < 5:
            raise _fail(data, begin, "Invalid \\uXXXX escape", next)
        var unit = _four_hex(data, first)
        if unit < 0:
            raise _fail(data, begin, "Invalid \\uXXXX escape", next)
        end = first + 4
        if (
            unit >= 0xD800
            and unit <= 0xDBFF
            and _chars_from(data, end, 7) == 7
            and data[end] == 0x5C
            and data[end + 1] == 0x75
        ):
            var low = _four_hex(data, end + 2)
            if low < 0:
                raise _fail(data, begin, "Invalid \\uXXXX escape", end + 1)
            if low >= 0xDC00 and low <= 0xDFFF:
                unit = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                end += 6
        _append_point(out, unit)


@fieldwise_init
struct _Number(Copyable, Movable):
    """A number token: its end and whether it is a float."""

    var end: Int
    var is_float: Bool


def _match_number(data: Span[UInt8, _], start: Int) -> _Number:
    """Match a number as CPython's scanner does; `end` is -1 for none."""
    var n = len(data)
    var at = start
    if data[at] == 0x2D:
        at += 1
        if at >= n:
            return _Number(-1, False)
    if data[at] >= 0x31 and data[at] <= 0x39:
        at += 1
        while at < n and data[at] >= 0x30 and data[at] <= 0x39:
            at += 1
    elif data[at] == 0x30:
        at += 1
    else:
        return _Number(-1, False)
    var is_float = False
    if (
        at < n - 1
        and data[at] == 0x2E
        and data[at + 1] >= 0x30
        and data[at + 1] <= 0x39
    ):
        is_float = True
        at += 2
        while at < n and data[at] >= 0x30 and data[at] <= 0x39:
            at += 1
    if at < n - 1 and (data[at] == 0x65 or data[at] == 0x45):
        var e_start = at
        at += 1
        if at < n - 1 and (data[at] == 0x2D or data[at] == 0x2B):
            at += 1
        while at < n and data[at] >= 0x30 and data[at] <= 0x39:
            at += 1
        if data[at - 1] >= 0x30 and data[at - 1] <= 0x39:
            is_float = True
        else:
            at = e_start
    return _Number(at, is_float)


def _int_node(
    mut doc: PyJson, data: Span[UInt8, _], start: Int, end: Int
) raises -> Int:
    """Add an int token, as `int(text)` reads it."""
    var negative = data[start] == 0x2D
    var first = start + 1 if negative else start
    var digits = end - first
    if digits > INT_DIGITS:
        raise Error(
            "Exceeds the limit ("
            + String(INT_DIGITS)
            + " digits) for integer string conversion: value has "
            + String(digits)
            + " digits; use sys.set_int_max_str_digits() to increase the limit"
        )
    var node = _Node(PY_INT)
    if digits == 1 and data[first] == 0x30:
        node.text = "0"
    else:
        node.text = String(unsafe_from_utf8=data[start:end])
    return doc._add(node^)


def _format_repr(negative: Bool, digits: String, point: Int) -> String:
    """Write shortest digits as `repr` places them; the value is
    0.digits * 10**point."""
    var sign = String("-") if negative else String()
    var count = digits.byte_length()
    if point <= -4 or point > 16:
        var mantissa = String(digits[byte=:1])
        if count > 1:
            mantissa += "." + String(digits[byte=1:])
        var exponent = point - 1
        var magnitude = String(abs(exponent))
        if magnitude.byte_length() < 2:
            magnitude = "0" + magnitude
        return (
            sign + mantissa + "e" + ("-" if exponent < 0 else "+") + magnitude
        )
    if point <= 0:
        return sign + "0." + "0" * (-point) + digits
    if point >= count:
        return sign + digits + "0" * (point - count) + ".0"
    return (
        sign + String(digits[byte=:point]) + "." + String(digits[byte=point:])
    )


def _power_of_ten(exponent: Int) -> Float64:
    """Return 10**exponent for 0 <= exponent <= 22, which is exact."""
    var value = 1.0
    for _ in range(exponent):
        value *= 10.0
    return value


def _float_node(
    mut doc: PyJson, data: Span[UInt8, _], start: Int, end: Int
) raises -> Int:
    """Add a float token, as `float(text)` reads it and `repr` writes it."""
    var negative = data[start] == 0x2D
    var at = start + 1 if negative else start
    var digits = List[UInt8]()
    var exponent = 0
    var point = False
    while at < end and data[at] != 0x65 and data[at] != 0x45:
        var byte = data[at]
        if byte == 0x2E:
            point = True
        else:
            if len(digits) > 0 or byte != 0x30:
                digits.append(byte)
            if point:
                exponent -= 1
        at += 1
    if at < end:
        at += 1
        var sign = 1
        if data[at] == 0x2D or data[at] == 0x2B:
            sign = -1 if data[at] == 0x2D else 1
            at += 1
        var written = 0
        while at < end:
            if written < 100000000:
                written = written * 10 + Int(data[at]) - 48
            at += 1
        exponent += sign * written
    while len(digits) > 0 and digits[len(digits) - 1] == 0x30:
        _ = digits.pop()
        exponent += 1
    var node = _Node(PY_FLOAT)
    var count = len(digits)
    if count == 0:
        node.number = -0.0 if negative else 0.0
        node.text = "-0.0" if negative else "0.0"
        return doc._add(node^)
    var text = String(unsafe_from_utf8=digits)
    var place = count + exponent
    if place > 310:
        node.number = Float64.MAX * 2
        if negative:
            node.number = -node.number
        node.text = "-inf" if negative else "inf"
        return doc._add(node^)
    if place < -330:
        node.number = -0.0 if negative else 0.0
        node.text = "-0.0" if negative else "0.0"
        return doc._add(node^)
    var value: Float64
    if count <= 15 and exponent >= -22 and exponent <= 22:
        var whole = Float64(Int(text))
        if exponent >= 0:
            value = whole * _power_of_ten(exponent)
        else:
            value = whole / _power_of_ten(-exponent)
    elif count <= 15 and exponent > 22 and count + exponent - 22 <= 15:
        var whole = Float64(Int(text) * Int(_power_of_ten(exponent - 22)))
        value = whole * _power_of_ten(22)
    else:
        value = parse_float(text + "e" + String(exponent))
    node.number = -value if negative else value
    if count <= 15 and place >= -306 and place <= 308:
        # At most 15 digits name one double in the normal range, and no
        # shorter digits name it, so they are its `repr` digits.
        node.text = _format_repr(negative, text, place)
    else:
        node.text = python_repr(node.number)
    return doc._add(node^)


def _close_dict(mut doc: PyJson, node: Int):
    """Keep the first position and the last value of a repeated key, as a
    Python dict built from pairs does."""
    var count = len(doc.nodes[node].keys)
    if count < 2:
        return
    var repeated = False
    if count <= 16:
        for i in range(1, count):
            for j in range(i):
                if doc.nodes[node].keys[i] == doc.nodes[node].keys[j]:
                    repeated = True
    else:
        var order = sorted_order(doc.nodes[node].keys)
        for i in range(1, count):
            if (
                doc.nodes[node].keys[order[i]]
                == doc.nodes[node].keys[order[i - 1]]
            ):
                repeated = True
    if not repeated:
        return
    var keys = List[String]()
    var items = List[Int]()
    for i in range(count):
        var name = doc.nodes[node].keys[i]
        var seen = False
        for k in keys:
            if k == name:
                seen = True
                break
        if seen:
            continue
        var value = doc.nodes[node].items[i]
        for j in range(i + 1, count):
            if doc.nodes[node].keys[j] == name:
                value = doc.nodes[node].items[j]
        keys.append(name)
        items.append(value)
    doc.nodes[node].keys = keys^
    doc.nodes[node].items = items^


@fieldwise_init
struct _Open(Copyable, Movable):
    """A container being read: its node and the key of its next value."""

    var node: Int
    var is_dict: Bool
    var key: String


def _scan(data: Span[UInt8, _], begin: Int) raises -> PyJson:
    """Read one JSON value and refuse extra data, as `json.loads` does on
    decoded text that starts at `begin`."""
    var doc = PyJson()
    var n = len(data)
    var at = _skip(data, begin)
    var stack = List[_Open]()
    var value: Int
    while True:
        # Read the value at `at`.
        if at >= n:
            raise _fail(data, begin, "Expecting value", at)
        var c = data[at]
        if c == 0x22:
            var read = _scan_string(data, begin, at + 1)
            value = doc.new_str(read[0])
            at = read[1]
        elif c == 0x7B or c == 0x5B:
            var is_dict = c == 0x7B
            if len(stack) >= MAX_DEPTH:
                raise Error(
                    RECURSION
                    + "maximum recursion depth exceeded while decoding a JSON "
                    + ("object" if is_dict else "array")
                    + " from a unicode string"
                )
            var made = doc.new_dict() if is_dict else doc.new_list()
            at = _skip(data, at + 1)
            if is_dict:
                if at < n and data[at] == 0x7D:
                    value = made
                    at += 1
                else:
                    if at >= n or data[at] != 0x22:
                        raise _fail(
                            data,
                            begin,
                            "Expecting property name enclosed in double quotes",
                            at,
                        )
                    var read = _scan_string(data, begin, at + 1)
                    at = _skip(data, read[1])
                    if at >= n or data[at] != 0x3A:
                        raise _fail(data, begin, "Expecting ':' delimiter", at)
                    at = _skip(data, at + 1)
                    stack.append(_Open(made, True, read[0]))
                    continue
            else:
                if at < n and data[at] == 0x5D:
                    value = made
                    at += 1
                else:
                    stack.append(_Open(made, False, String()))
                    continue
        elif c == 0x6E and at + 3 < n and _word(data, at, "null"):
            value = doc.new_none()
            at += 4
        elif c == 0x74 and at + 3 < n and _word(data, at, "true"):
            value = doc.new_bool(True)
            at += 4
        elif c == 0x66 and at + 4 < n and _word(data, at, "false"):
            value = doc.new_bool(False)
            at += 5
        elif c == 0x4E and at + 2 < n and _word(data, at, "NaN"):
            value = doc.new_float(Float64.MAX * 2 - Float64.MAX * 2)
            at += 3
        elif c == 0x49 and at + 7 < n and _word(data, at, "Infinity"):
            value = doc.new_float(Float64.MAX * 2)
            at += 8
        elif c == 0x2D and at + 8 < n and _word(data, at, "-Infinity"):
            value = doc.new_float(-(Float64.MAX * 2))
            at += 9
        else:
            var number = _match_number(data, at)
            if number.end < 0:
                raise _fail(data, begin, "Expecting value", at)
            if number.is_float:
                value = _float_node(doc, data, at, number.end)
            else:
                value = _int_node(doc, data, at, number.end)
            at = number.end
        # Attach the value to the open containers that it completes.
        var more = False
        while len(stack) > 0:
            var top = len(stack) - 1
            var holder = stack[top].node
            if stack[top].is_dict:
                doc.nodes[holder].keys.append(stack[top].key)
                doc.nodes[holder].items.append(value)
                at = _skip(data, at)
                if at < n and data[at] == 0x7D:
                    at += 1
                    _close_dict(doc, holder)
                    value = holder
                    _ = stack.pop()
                    continue
                if at >= n or data[at] != 0x2C:
                    raise _fail(data, begin, "Expecting ',' delimiter", at)
                at = _skip(data, at + 1)
                if at >= n or data[at] != 0x22:
                    raise _fail(
                        data,
                        begin,
                        "Expecting property name enclosed in double quotes",
                        at,
                    )
                var read = _scan_string(data, begin, at + 1)
                at = _skip(data, read[1])
                if at >= n or data[at] != 0x3A:
                    raise _fail(data, begin, "Expecting ':' delimiter", at)
                at = _skip(data, at + 1)
                stack[top].key = read[0]
                more = True
                break
            doc.nodes[holder].items.append(value)
            at = _skip(data, at)
            if at < n and data[at] == 0x5D:
                at += 1
                value = holder
                _ = stack.pop()
                continue
            if at >= n or data[at] != 0x2C:
                raise _fail(data, begin, "Expecting ',' delimiter", at)
            at = _skip(data, at + 1)
            more = True
            break
        if not more:
            break
    at = _skip(data, at)
    if at != n:
        raise _fail(data, begin, "Extra data", at)
    doc.root = value
    return doc^


def _word(data: Span[UInt8, _], at: Int, word: StaticString) -> Bool:
    """Return whether the bytes at `at` spell `word`."""
    var letters = word.as_bytes()
    for index in range(len(letters)):
        if data[at + index] != letters[index]:
            return False
    return True


# --- Writing JSON -------------------------------------------------------------------


def _less(a: String, b: String) -> Bool:
    """Compare two str values by code point, as Python sorts them."""
    var x = a.as_bytes()
    var y = b.as_bytes()
    var count = min(len(x), len(y))
    for index in range(count):
        if x[index] != y[index]:
            return x[index] < y[index]
    return len(x) < len(y)


def sorted_order(keys: List[String]) -> List[Int]:
    """Return the positions of the keys in Python's sorted order.

    Args:
        keys: The keys.

    Returns:
        Their positions, sorted by key and then by position.
    """
    var order = List[Int](capacity=len(keys))
    for index in range(len(keys)):
        order.append(index)
    var width = 1
    var scratch = List[Int](length=len(keys), fill=0)
    while width < len(order):
        var left = 0
        while left < len(order):
            var middle = min(left + width, len(order))
            var right = min(left + 2 * width, len(order))
            var i = left
            var j = middle
            var k = left
            while i < middle and j < right:
                if _less(keys[order[j]], keys[order[i]]):
                    scratch[k] = order[j]
                    j += 1
                else:
                    scratch[k] = order[i]
                    i += 1
                k += 1
            while i < middle:
                scratch[k] = order[i]
                i += 1
                k += 1
            while j < right:
                scratch[k] = order[j]
                j += 1
                k += 1
            left = right
        for index in range(len(order)):
            order[index] = scratch[index]
        width *= 2
    return order^


def _append_text(mut out: List[UInt8], text: String):
    """Append ASCII text."""
    for byte in text.as_bytes():
        out.append(byte)


def _append_escape(mut out: List[UInt8], unit: Int):
    """Append `\\u` and four lowercase hexadecimal digits."""
    out.append(0x5C)
    out.append(0x75)
    for shift in [12, 8, 4, 0]:
        out.append(_HEX.as_bytes()[(unit >> shift) & 15])


def _append_quoted(mut out: List[UInt8], text: String):
    """Append a str as `json.dumps` writes it with `ensure_ascii`."""
    out.append(0x22)
    var data = text.as_bytes()
    var at = 0
    while at < len(data):
        var byte = data[at]
        if byte < 0x80:
            at += 1
            if byte == 0x22:
                out.append(0x5C)
                out.append(0x22)
            elif byte == 0x5C:
                out.append(0x5C)
                out.append(0x5C)
            elif byte == 0x0A:
                out.append(0x5C)
                out.append(0x6E)
            elif byte == 0x0D:
                out.append(0x5C)
                out.append(0x72)
            elif byte == 0x09:
                out.append(0x5C)
                out.append(0x74)
            elif byte == 0x08:
                out.append(0x5C)
                out.append(0x62)
            elif byte == 0x0C:
                out.append(0x5C)
                out.append(0x66)
            elif byte < 0x20 or byte == 0x7F:
                _append_escape(out, Int(byte))
            else:
                out.append(byte)
            continue
        var step = _utf8_step(data, at, len(data))
        var point: Int
        if step[0] > 0:
            point = step[1]
            at += step[0]
        else:
            point = _surrogate_at(data, at, len(data))
            if point < 0:
                point = 0xFFFD
                at += 1
            else:
                at += 3
        if point > 0xFFFF:
            var value = point - 0x10000
            _append_escape(out, 0xD800 | (value >> 10))
            _append_escape(out, 0xDC00 | (value & 0x3FF))
        else:
            _append_escape(out, point)
    out.append(0x22)


@fieldwise_init
struct _Frame(Copyable, Movable):
    """A container being written: its node, its order and the next slot."""

    var node: Int
    var order: List[Int]
    var next: Int


def _write(doc: PyJson, node: Int, mut out: List[UInt8], emit: Bool) raises:
    """Write a value canonically, or only walk it in the same order when
    `emit` is False, and raise Python's first error."""
    var stack = List[_Frame]()
    var current = node
    while True:
        # Write `current`, or open it.
        var kind = doc.nodes[current].kind
        if kind == PY_DICT or kind == PY_LIST:
            if len(stack) >= MAX_DEPTH:
                raise Error(
                    RECURSION
                    + "maximum recursion depth exceeded while encoding a JSON"
                    " object"
                )
            var order: List[Int]
            if kind == PY_DICT:
                order = sorted_order(doc.nodes[current].keys)
            else:
                order = List[Int]()
                for index in range(len(doc.nodes[current].items)):
                    order.append(index)
            if emit:
                out.append(UInt8(0x7B if kind == PY_DICT else 0x5B))
            stack.append(_Frame(current, order^, 0))
        elif emit:
            if kind == PY_STR:
                _append_quoted(out, doc.nodes[current].text)
            elif kind == PY_INT:
                _append_text(out, doc.nodes[current].text)
            elif kind == PY_FLOAT:
                var number = doc.nodes[current].number
                if isnan(number) or isinf(number):
                    raise Error(
                        "Out of range float values are not JSON compliant: "
                        + doc.nodes[current].text
                    )
                _append_text(out, doc.nodes[current].text)
            elif kind == PY_BOOL:
                _append_text(
                    out, "true" if doc.nodes[current].flag else "false"
                )
            else:
                _append_text(out, "null")
        elif kind == PY_FLOAT:
            var number = doc.nodes[current].number
            if isnan(number) or isinf(number):
                raise Error(
                    "Out of range float values are not JSON compliant: "
                    + doc.nodes[current].text
                )
        # Find the next value to write.
        var found = False
        while len(stack) > 0:
            var top = len(stack) - 1
            var holder = stack[top].node
            var slot = stack[top].next
            if slot < len(stack[top].order):
                var index = stack[top].order[slot]
                stack[top].next = slot + 1
                if doc.nodes[holder].kind == PY_DICT:
                    if emit:
                        if slot > 0:
                            out.append(0x2C)
                        _append_quoted(out, doc.nodes[holder].keys[index])
                        out.append(0x3A)
                elif emit and slot > 0:
                    out.append(0x2C)
                current = doc.nodes[holder].items[index]
                found = True
                break
            if emit:
                out.append(
                    UInt8(0x7D if doc.nodes[holder].kind == PY_DICT else 0x5D)
                )
            _ = stack.pop()
        if not found:
            return


def canonical_bytes(doc: PyJson, node: Int) raises -> List[UInt8]:
    """Return a value's canonical JSON bytes.

    The bytes are `json.dumps(value, sort_keys=True, separators=(",", ":"),
    ensure_ascii=True, allow_nan=False).encode()`.

    Args:
        doc: The document.
        node: The value.

    Returns:
        The ASCII bytes.

    Raises:
        Error: With Python's text for a float that is not finite, or a
            `RecursionError: ` text for nesting past `MAX_DEPTH`.
    """
    var out = List[UInt8]()
    _write(doc, node, out, True)
    return out^


def dumps_canonical(doc: PyJson, node: Int) raises -> String:
    """Return a value's canonical JSON text.

    Args:
        doc: The document.
        node: The value.

    Returns:
        The text that `canonical_bytes` gives.

    Raises:
        Error: As `canonical_bytes` does.
    """
    return String(unsafe_from_utf8=canonical_bytes(doc, node))


def check_canonical(doc: PyJson, node: Int) raises:
    """Raise what `canonical_bytes` would raise, without writing.

    Args:
        doc: The document.
        node: The value.

    Raises:
        Error: As `canonical_bytes` does, for the first value in sorted
            order that it refuses.
    """
    # Most values pass: look for a refused float or deep nesting in any
    # order first, then find the first one in sorted order.
    var pending: List[Tuple[Int, Int]] = [(node, 0)]
    var clean = True
    while len(pending) > 0:
        var pair = pending.pop()
        ref entry = doc.nodes[pair[0]]
        if entry.kind == PY_FLOAT:
            if isnan(entry.number) or isinf(entry.number):
                clean = False
                break
        elif entry.kind == PY_DICT or entry.kind == PY_LIST:
            if pair[1] >= MAX_DEPTH:
                clean = False
                break
            for child in entry.items:
                pending.append((child, pair[1] + 1))
    if clean:
        return
    var out = List[UInt8]()
    _write(doc, node, out, False)


# --- Python's == ----------------------------------------------------------------------


def _int_value(text: String) -> Tuple[Bool, Int]:
    """Return (True, value) for an int's digits that fit in an Int."""
    if text.byte_length() > 18:
        return (False, 0)
    try:
        return (True, Int(text))
    except:
        return (False, 0)


def _int_equals_float(text: String, value: Float64) raises -> Bool:
    """Return whether an int equals a float exactly."""
    if isnan(value) or isinf(value):
        return False
    if value != Float64(Int(value)) if abs(value) < 9.0e18 else False:
        return False
    if abs(value) < 9.0e18:
        var small = _int_value(text)
        return small[0] and small[1] == Int(value)
    var exact = Fraction.from_float(value)
    if exact.denominator != BigInt(1):
        return False
    return exact.numerator == BigInt.parse(text)


def _numeric(doc: PyJson, node: Int) -> Bool:
    """Return whether a value is a bool, an int or a float."""
    var kind = doc.kind(node)
    return kind == PY_BOOL or kind == PY_INT or kind == PY_FLOAT


def _numbers_equal(a: PyJson, x: Int, b: PyJson, y: Int) raises -> Bool:
    """Compare two numbers as Python's `==` does."""
    var kx = a.kind(x)
    var ky = b.kind(y)
    var tx = (String("1") if a.flag(x) else String("0")) if kx == PY_BOOL else (
        a.text(x)
    )
    var ty = (String("1") if b.flag(y) else String("0")) if ky == PY_BOOL else (
        b.text(y)
    )
    if kx != PY_FLOAT and ky != PY_FLOAT:
        return tx == ty
    if kx == PY_FLOAT and ky == PY_FLOAT:
        return a.number(x) == b.number(y)
    if kx == PY_FLOAT:
        return _int_equals_float(ty, a.number(x))
    return _int_equals_float(tx, b.number(y))


def py_equal(a: PyJson, x: Int, b: PyJson, y: Int) raises -> Bool:
    """Compare two values as Python's `==` does.

    Args:
        a: The first document.
        x: A value in `a`, or `MISSING` for `None`.
        b: The second document.
        y: A value in `b`, or `MISSING` for `None`.

    Returns:
        True when the values are equal. A NaN equals nothing.

    Raises:
        Error: Never for valid nodes; it signals an internal failure.
    """
    var pending: List[Tuple[Int, Int]] = [(x, y)]
    while len(pending) > 0:
        var pair = pending.pop()
        var p = pair[0]
        var q = pair[1]
        if _numeric(a, p) and _numeric(b, q):
            if not _numbers_equal(a, p, b, q):
                return False
            continue
        var kind = a.kind(p)
        if kind != b.kind(q):
            return False
        if kind == PY_NONE:
            continue
        if kind == PY_STR:
            if a.text(p) != b.text(q):
                return False
            continue
        if a.length(p) != b.length(q):
            return False
        if kind == PY_LIST:
            for index in range(a.length(p)):
                pending.append((a.value(p, index), b.value(q, index)))
            continue
        for index in range(a.length(p)):
            var other = b.find(q, a.key(p, index))
            if other == MISSING:
                return False
            pending.append((a.value(p, index), other))
    return True
