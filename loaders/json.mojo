# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""JSON: the text a glTF file is written in, read into a tree of nodes.

Mojo's standard library has no JSON reader, and a glTF loader needs one, so
this is a reader of exactly RFC 8259: objects, arrays, strings with their
escapes, numbers, `true`, `false` and `null`, and nothing more. No
comments, no trailing commas, no bare words, no single quotes. A file that
bends the grammar is refused with the byte it went wrong at, for the reason
`render.png` checks its structure: a reader that guesses hides the file
that is wrong.

**One arena, not a recursive type.** A value holds values, and a struct
that holds a `List` of itself is a shape Mojo does not have a good spelling
for. So every value is a `JsonNode` in one `List`, and a node names its
children by index. The root is node zero. `JsonDocument` reads the tree
by index: `get` walks into an object by key, `at` into an array by
position, and the leaf accessors say what a node holds, or raise when it
holds something else, so a caller that expects a number is told when it
finds a string rather than reading zero.

Numbers are kept as `Float64`, which holds every integer a glTF file
needs -- a byte offset, a count, an index -- exactly, up to fifty-three
bits. `integer` refuses a number with a fraction.
"""

from std.math import isfinite

# What a node holds.


@fieldwise_init
struct JsonKind(Equatable, ImplicitlyCopyable, Writable):
    """What a JSON value is, as a type rather than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six kinds there are."""
        return (
            self == OBJECT
            or self == ARRAY
            or self == STRING
            or self == NUMBER
            or self == BOOLEAN
            or self == NULL
        )


comptime OBJECT = JsonKind(0)
comptime ARRAY = JsonKind(1)
comptime STRING = JsonKind(2)
comptime NUMBER = JsonKind(3)
comptime BOOLEAN = JsonKind(4)
comptime NULL = JsonKind(5)

# What `JsonDocument.get` returns for a key an object does not have.
comptime NO_NODE = -1
# How deep an object or array can sit inside others. A file nested past
# this is refused rather than read on a stack that has no more room.
comptime MAX_DEPTH = 256


struct JsonNode(Copyable, Movable):
    """One value: its kind and, by kind, its number, its text, its truth,
    or its children."""

    var kind: JsonKind
    var number: Float64
    var text: String
    var flag: Bool
    # An object's keys, one per child, in file order.
    var keys: List[String]
    # An object's or an array's children, as indices into the document.
    var children: List[Int]

    def __init__(out self, kind: JsonKind):
        """Start an empty node of `kind`.

        Args:
            kind: What the node holds.
        """
        self.kind = kind
        self.number = 0
        self.text = String()
        self.flag = False
        self.keys = List[String]()
        self.children = List[Int]()


struct JsonDocument(Movable):
    """A parsed JSON text: every value as a node, the root at zero."""

    var nodes: List[JsonNode]

    def __init__(out self):
        """Start with no nodes."""
        self.nodes = List[JsonNode]()

    def root(self) -> Int:
        """Return the root node's index."""
        return 0

    def _check(self, node: Int) raises:
        """Refuse an index that names no node."""
        if node < 0 or node >= len(self.nodes):
            raise Error("JSON: no node at index " + String(node))

    def kind(self, node: Int) raises -> JsonKind:
        """Return what a node holds.

        Args:
            node: The node's index.

        Returns:
            Its kind.

        Raises:
            Error: If the index names no node.
        """
        self._check(node)
        return self.nodes[node].kind

    def length(self, node: Int) raises -> Int:
        """Return how many children an object or an array has.

        Args:
            node: The node's index.

        Returns:
            Its child count.

        Raises:
            Error: If the node is neither an object nor an array.
        """
        self._check(node)
        ref found = self.nodes[node]
        if found.kind != OBJECT and found.kind != ARRAY:
            raise Error("JSON: only an object or an array has a length")
        return len(found.children)

    def has(self, node: Int, key: String) raises -> Bool:
        """Return True if an object has a key.

        Args:
            node: The object's index.
            key: The key.

        Returns:
            Whether the key is there.

        Raises:
            Error: If the node is not an object.
        """
        return self.get(node, key) != NO_NODE

    def get(self, node: Int, key: String) raises -> Int:
        """Return the child of an object under a key, or `NO_NODE`.

        Args:
            node: The object's index.
            key: The key.

        Returns:
            The child's index, or `NO_NODE` when the key is absent. The
            last of two equal keys wins, as `JSON.parse` has it.

        Raises:
            Error: If the node is not an object.
        """
        self._check(node)
        ref found = self.nodes[node]
        if found.kind != OBJECT:
            raise Error("JSON: only an object has keys")
        var answer = NO_NODE
        for index in range(len(found.keys)):
            if found.keys[index] == key:
                answer = found.children[index]
        return answer

    def key(self, node: Int, index: Int) raises -> String:
        """Return an object's key by position.

        Args:
            node: The object's index.
            index: Which key, in file order.

        Returns:
            The key.

        Raises:
            Error: If the node is not an object or the position is outside
                its keys.
        """
        self._check(node)
        ref found = self.nodes[node]
        if found.kind != OBJECT:
            raise Error("JSON: only an object has keys")
        if index < 0 or index >= len(found.keys):
            raise Error("JSON: no key at position " + String(index))
        return found.keys[index]

    def at(self, node: Int, index: Int) raises -> Int:
        """Return a child of an array or an object by position.

        Args:
            node: The array's or object's index.
            index: Which child, in file order.

        Returns:
            The child's index.

        Raises:
            Error: If the node is neither an array nor an object, or the
                position is outside its children.
        """
        self._check(node)
        ref found = self.nodes[node]
        if found.kind != ARRAY and found.kind != OBJECT:
            raise Error("JSON: only an array or an object has children")
        if index < 0 or index >= len(found.children):
            raise Error("JSON: no child at position " + String(index))
        return found.children[index]

    def number(self, node: Int) raises -> Float64:
        """Return a number.

        Args:
            node: The node's index.

        Returns:
            The number.

        Raises:
            Error: If the node is not a number.
        """
        self._check(node)
        ref found = self.nodes[node]
        if found.kind != NUMBER:
            raise Error("JSON: expected a number")
        return found.number

    def integer(self, node: Int) raises -> Int:
        """Return a number that is whole.

        Args:
            node: The node's index.

        Returns:
            The number as an `Int`.

        Raises:
            Error: If the node is not a number, or the number has a
                fraction or is too large for an `Int`.
        """
        var value = self.number(node)
        if value != Float64(Int(value)) or value > 9.0e15 or value < -9.0e15:
            raise Error("JSON: expected a whole number")
        return Int(value)

    def string(self, node: Int) raises -> String:
        """Return a string.

        Args:
            node: The node's index.

        Returns:
            The text, its escapes resolved.

        Raises:
            Error: If the node is not a string.
        """
        self._check(node)
        ref found = self.nodes[node]
        if found.kind != STRING:
            raise Error("JSON: expected a string")
        return found.text

    def boolean(self, node: Int) raises -> Bool:
        """Return `true` or `false`.

        Args:
            node: The node's index.

        Returns:
            The truth.

        Raises:
            Error: If the node is not a boolean.
        """
        self._check(node)
        ref found = self.nodes[node]
        if found.kind != BOOLEAN:
            raise Error("JSON: expected true or false")
        return found.flag

    def is_null(self, node: Int) raises -> Bool:
        """Return True if a node is `null`.

        Args:
            node: The node's index.

        Returns:
            Whether it is null.

        Raises:
            Error: If the index names no node.
        """
        self._check(node)
        return self.nodes[node].kind == NULL


def parse_json(text: String) raises -> JsonDocument:
    """Read a JSON text.

    Args:
        text: The whole text.

    Returns:
        The document, its root at node zero.

    Raises:
        Error: If the text is not JSON: an unexpected byte, an unterminated
            string or container, a bad escape, a number outside the
            grammar or beyond a `Float64`, anything after the root value,
            or nesting past `MAX_DEPTH`. The message names the byte offset.
    """
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    var parser = _Parser(bytes^)
    var document = JsonDocument()
    parser.skip_space()
    _ = parser.value(document, 0)
    parser.skip_space()
    if not parser.done():
        raise Error(parser.where() + "text after the root value")
    return document^


struct _Parser(Movable):
    """The reader's cursor over the bytes."""

    var bytes: List[UInt8]
    var at: Int

    def __init__(out self, var bytes: List[UInt8]):
        self.bytes = bytes^
        self.at = 0

    def where(self) -> String:
        """Return the prefix of an error: where the cursor stands."""
        return "JSON at byte " + String(self.at) + ": "

    def done(self) -> Bool:
        """Return True once every byte is read."""
        return self.at >= len(self.bytes)

    def peek(self) -> Int:
        """Return the byte under the cursor, or -1 past the end."""
        if self.done():
            return -1
        return Int(self.bytes[self.at])

    def skip_space(mut self):
        """Step over the four whitespace bytes JSON allows."""
        while not self.done():
            var byte = self.peek()
            if byte == 32 or byte == 9 or byte == 10 or byte == 13:
                self.at += 1
            else:
                return

    def expect(mut self, byte: Int) raises:
        """Step over one byte, refusing any other."""
        if self.peek() != byte:
            raise Error(self.where() + "expected '" + String(chr(byte)) + "'")
        self.at += 1

    def value(mut self, mut document: JsonDocument, depth: Int) raises -> Int:
        """Read one value at the cursor and return its node index."""
        if depth > MAX_DEPTH:
            raise Error(self.where() + "nested too deep")
        var byte = self.peek()
        if byte == 123:
            return self.object(document, depth)
        if byte == 91:
            return self.array(document, depth)
        if byte == 34:
            var node = JsonNode(STRING)
            node.text = self.string()
            document.nodes.append(node^)
            return len(document.nodes) - 1
        if byte == 116:
            self.literal("true")
            var node = JsonNode(BOOLEAN)
            node.flag = True
            document.nodes.append(node^)
            return len(document.nodes) - 1
        if byte == 102:
            self.literal("false")
            document.nodes.append(JsonNode(BOOLEAN))
            return len(document.nodes) - 1
        if byte == 110:
            self.literal("null")
            document.nodes.append(JsonNode(NULL))
            return len(document.nodes) - 1
        if byte == 45 or (byte >= 48 and byte <= 57):
            var node = JsonNode(NUMBER)
            node.number = self.number()
            document.nodes.append(node^)
            return len(document.nodes) - 1
        if byte < 0:
            raise Error(self.where() + "expected a value, found the end")
        raise Error(self.where() + "expected a value")

    def object(mut self, mut document: JsonDocument, depth: Int) raises -> Int:
        """Read an object at the cursor: its node is placed before its
        children and filled in after them."""
        self.expect(123)
        document.nodes.append(JsonNode(OBJECT))
        var index = len(document.nodes) - 1
        var keys = List[String]()
        var children = List[Int]()
        self.skip_space()
        if self.peek() == 125:
            self.at += 1
            return index
        while True:
            self.skip_space()
            if self.peek() != 34:
                raise Error(self.where() + "expected a key in quotes")
            keys.append(self.string())
            self.skip_space()
            self.expect(58)
            self.skip_space()
            children.append(self.value(document, depth + 1))
            self.skip_space()
            var byte = self.peek()
            if byte == 44:
                self.at += 1
                continue
            if byte == 125:
                self.at += 1
                break
            raise Error(self.where() + "expected ',' or '}'")
        document.nodes[index].keys = keys^
        document.nodes[index].children = children^
        return index

    def array(mut self, mut document: JsonDocument, depth: Int) raises -> Int:
        """Read an array at the cursor, as `object` reads an object."""
        self.expect(91)
        document.nodes.append(JsonNode(ARRAY))
        var index = len(document.nodes) - 1
        var children = List[Int]()
        self.skip_space()
        if self.peek() == 93:
            self.at += 1
            return index
        while True:
            self.skip_space()
            children.append(self.value(document, depth + 1))
            self.skip_space()
            var byte = self.peek()
            if byte == 44:
                self.at += 1
                continue
            if byte == 93:
                self.at += 1
                break
            raise Error(self.where() + "expected ',' or ']'")
        document.nodes[index].children = children^
        return index

    def literal(mut self, word: String) raises:
        """Step over `true`, `false` or `null`, whole."""
        var expected = word.as_bytes()
        for offset in range(len(expected)):  # pragma: no branch
            if (
                self.at + offset >= len(self.bytes)
                or self.bytes[self.at + offset] != expected[offset]
            ):
                raise Error(self.where() + "expected " + word)
        self.at += len(expected)

    def hex_digit(mut self) raises -> Int:
        """Read one hex digit of a `\\u` escape."""
        var byte = self.peek()
        var digit: Int
        if byte >= 48 and byte <= 57:
            digit = byte - 48
        elif byte >= 97 and byte <= 102:
            digit = byte - 87
        elif byte >= 65 and byte <= 70:
            digit = byte - 55
        else:
            raise Error(self.where() + "expected a hex digit")
        self.at += 1
        return digit

    def code_unit(mut self) raises -> Int:
        """Read the four hex digits of a `\\u` escape."""
        var unit = 0
        for _ in range(4):  # pragma: no branch
            unit = unit * 16 + self.hex_digit()
        return unit

    def string(mut self) raises -> String:
        """Read a string at the cursor, resolving its escapes into UTF-8."""
        self.expect(34)
        var out = List[UInt8]()
        while True:
            var byte = self.peek()
            if byte < 0:
                raise Error(self.where() + "unterminated string")
            self.at += 1
            if byte == 34:
                break
            if byte < 32:
                raise Error(self.where() + "a control byte inside a string")
            if byte != 92:
                out.append(UInt8(byte))
                continue
            var escaped = self.peek()
            self.at += 1
            if escaped == 34 or escaped == 92 or escaped == 47:
                out.append(UInt8(escaped))
            elif escaped == 98:
                out.append(8)
            elif escaped == 102:
                out.append(12)
            elif escaped == 110:
                out.append(10)
            elif escaped == 114:
                out.append(13)
            elif escaped == 116:
                out.append(9)
            elif escaped == 117:
                var point = self.code_unit()
                if point >= 0xD800 and point <= 0xDBFF:
                    # The high half of a surrogate pair: the low half must
                    # follow as another escape.
                    if self.peek() != 92:
                        raise Error(self.where() + "a lone high surrogate")
                    self.at += 1
                    if self.peek() != 117:
                        raise Error(self.where() + "a lone high surrogate")
                    self.at += 1
                    var low = self.code_unit()
                    if low < 0xDC00 or low > 0xDFFF:
                        raise Error(self.where() + "a lone high surrogate")
                    point = 0x10000 + ((point - 0xD800) << 10) + (low - 0xDC00)
                elif point >= 0xDC00 and point <= 0xDFFF:
                    raise Error(self.where() + "a lone low surrogate")
                _append_utf8(out, point)
            else:
                raise Error(self.where() + "unknown escape")
        return String(unsafe_from_utf8=out)

    def digits(mut self) raises -> Int:
        """Step over one or more digits and return how many."""
        var count = 0
        while self.peek() >= 48 and self.peek() <= 57:
            self.at += 1
            count += 1
        if count == 0:
            raise Error(self.where() + "expected a digit")
        return count

    def number(mut self) raises -> Float64:
        """Read a number at the cursor, held to JSON's grammar."""
        var start = self.at
        if self.peek() == 45:
            self.at += 1
        if self.peek() == 48:
            self.at += 1
        else:
            _ = self.digits()
        if self.peek() == 46:
            self.at += 1
            _ = self.digits()
        if self.peek() == 101 or self.peek() == 69:
            self.at += 1
            if self.peek() == 43 or self.peek() == 45:
                self.at += 1
            _ = self.digits()
        var text = List[UInt8]()
        for index in range(start, self.at):  # pragma: no branch
            text.append(self.bytes[index])
        var value = Float64(String(unsafe_from_utf8=text))
        if not isfinite(value):
            raise Error(self.where() + "a number beyond a Float64")
        return value


def _append_utf8(mut out: List[UInt8], point: Int):
    """Append a code point as UTF-8."""
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
