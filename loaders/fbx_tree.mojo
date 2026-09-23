# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An FBX file read into a tree of nodes, from its text or its bytes:
three.js's `TextParser` and `BinaryParser` in `FBXLoader.js`.

**What an FBX file is.** A tree of named nodes, each with a list of
properties -- whole numbers, numbers, strings, raw bytes, and arrays of
numbers -- and child nodes. The same tree is written two ways. The ASCII
form is text: `Name: value, value, ... { children }`, with an array
written `Name: *count { a: value, value, ... }`. The binary form is a
header, then records that each give their end offset, their property
count and their name, then the properties typed by one letter, then the
child records. An array in a binary file can be compressed with zlib,
which `render.inflate` expands.

`parse_fbx` reads either into an `FbxDocument`: one `FbxNode` per node in
one list, as `loaders.json` holds a tree, with node zero a nameless root
whose children are the file's top-level nodes. An ASCII array's `a` child
is folded into its node as one array property, so a node reads the same
from either form.

**Strings.** A binary file writes an object's name as `Name\\x00\\x01Class`,
and three.js's `BinaryReader.getString` stops at the zero byte, so a
binary string is kept up to its first zero byte. An ASCII file writes the
same name as `"Class::Name"`, kept as written: `object_name` strips it.

**What is refused.** An ASCII file older than version 7000 and a binary
file older than 6400, as three.js refuses them; a truncated record or
property, a record whose children run past its end, an unknown property
type, an array encoding other than raw or zlib, or a zlib array that
expands to the wrong length; an ASCII node without `:`, an unbalanced
`{` or `}`, an unterminated string, or an array whose `a` holds a count
other than the one its `*count` declares.
"""

from render.inflate import zlib_inflate
from std.memory import bitcast

# What `FbxDocument.child` returns when there is no such child.
comptime NO_FBX_NODE = -1
# How deep a node can sit inside others. Deeper is refused, since the
# binary reader walks records by recursion.
comptime MAX_FBX_DEPTH = 256
# The first bytes of a binary file: `Kaydara FBX Binary`, two spaces and
# a zero byte.
comptime BINARY_MAGIC = "Kaydara FBX Binary  \x00"
# Where a binary file's version is: after the magic and two more bytes.
comptime BINARY_VERSION_AT = 23
comptime BINARY_HEADER_BYTES = 27
# The oldest versions three.js reads.
comptime MIN_ASCII_VERSION = 7000
comptime MIN_BINARY_VERSION = 6400
# From version 7500 a record's three sizes are 64 bits, not 32.
comptime WIDE_RECORD_VERSION = 7500


@fieldwise_init
struct FbxFormat(Equatable, ImplicitlyCopyable, Writable):
    """Which of its two forms an FBX file is written in, as a type rather
    than a bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the two forms there are."""
        return self == FBX_ASCII or self == FBX_BINARY


# Text: `Name: value, value { ... }`.
comptime FBX_ASCII = FbxFormat(0)
# Bytes: the `Kaydara FBX Binary` header and records.
comptime FBX_BINARY = FbxFormat(1)


@fieldwise_init
struct FbxPropertyKind(Equatable, ImplicitlyCopyable, Writable):
    """What one property of an FBX node holds, as a type rather than a
    bare int."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the six kinds there are."""
        return (
            self == FBX_INTEGER
            or self == FBX_NUMBER
            or self == FBX_STRING
            or self == FBX_INTEGERS
            or self == FBX_NUMBERS
            or self == FBX_BYTES
        )


# A whole number: binary `Y`, `C`, `I` and `L`, or ASCII digits.
comptime FBX_INTEGER = FbxPropertyKind(0)
# A number with a fraction: binary `F` and `D`, or ASCII.
comptime FBX_NUMBER = FbxPropertyKind(1)
# Text: binary `S`, or an ASCII quoted string or bare word.
comptime FBX_STRING = FbxPropertyKind(2)
# An array of whole numbers: binary `i`, `l`, `b` and `c`, or an ASCII
# array of whole numbers.
comptime FBX_INTEGERS = FbxPropertyKind(3)
# An array of numbers: binary `f` and `d`, or an ASCII array with a
# fraction in it.
comptime FBX_NUMBERS = FbxPropertyKind(4)
# Raw bytes: binary `R`, such as an embedded image.
comptime FBX_BYTES = FbxPropertyKind(5)


struct FbxProperty(Copyable, Movable):
    """One property of a node: its kind, and by kind its value."""

    var kind: FbxPropertyKind
    var integer: Int
    var number: Float64
    var text: String
    var integers: List[Int]
    var numbers: List[Float64]
    var bytes: List[UInt8]

    def __init__(out self, kind: FbxPropertyKind):
        """Start an empty property of a kind.

        Args:
            kind: What it holds.
        """
        self.kind = kind
        self.integer = 0
        self.number = 0
        self.text = String()
        self.integers = List[Int]()
        self.numbers = List[Float64]()
        self.bytes = List[UInt8]()


def integer_property(value: Int) -> FbxProperty:
    """Return a whole-number property.

    Args:
        value: The number.

    Returns:
        The property.
    """
    var made = FbxProperty(FBX_INTEGER)
    made.integer = value
    return made^


def number_property(value: Float64) -> FbxProperty:
    """Return a number property.

    Args:
        value: The number.

    Returns:
        The property.
    """
    var made = FbxProperty(FBX_NUMBER)
    made.number = value
    return made^


def string_property(var value: String) -> FbxProperty:
    """Return a string property.

    Args:
        value: The text.

    Returns:
        The property.
    """
    var made = FbxProperty(FBX_STRING)
    made.text = value^
    return made^


struct FbxNode(Copyable, Movable):
    """One node: its name, its properties and its children."""

    var name: String
    var properties: List[FbxProperty]
    # The child nodes, as indices into the document, in file order.
    var children: List[Int]

    def __init__(out self, var name: String):
        """Start a node with no properties and no children.

        Args:
            name: Its name.
        """
        self.name = name^
        self.properties = List[FbxProperty]()
        self.children = List[Int]()


struct FbxDocument(Movable):
    """A parsed FBX file: every node in one list, a nameless root at
    zero."""

    var nodes: List[FbxNode]
    var format: FbxFormat
    # The file's version: `FBXVersion` for text, the header's for bytes.
    var version: Int

    def __init__(out self, format: FbxFormat):
        """Start with the root alone.

        Args:
            format: Which form the file is written in.
        """
        self.nodes = List[FbxNode]()
        self.nodes.append(FbxNode(String()))
        self.format = format
        self.version = 0

    def root(self) -> Int:
        """Return the root's index, whose children are the top-level
        nodes."""
        return 0

    def _check(self, node: Int) raises:
        """Refuse an index that names no node."""
        if node < 0 or node >= len(self.nodes):
            raise Error("FBX: no node at index " + String(node))

    def name(self, node: Int) raises -> String:
        """Return a node's name.

        Args:
            node: The node's index.

        Returns:
            Its name.

        Raises:
            Error: If the index names no node.
        """
        self._check(node)
        return self.nodes[node].name

    def children(self, node: Int) raises -> List[Int]:
        """Return a node's children.

        Args:
            node: The node's index.

        Returns:
            Their indices, in file order.

        Raises:
            Error: If the index names no node.
        """
        self._check(node)
        return self.nodes[node].children.copy()

    def children_named(self, node: Int, name: String) raises -> List[Int]:
        """Return a node's children of one name.

        Args:
            node: The node's index.
            name: The name to match.

        Returns:
            Their indices, in file order.

        Raises:
            Error: If the index names no node.
        """
        self._check(node)
        var found = List[Int]()
        for child in self.nodes[node].children:
            if self.nodes[child].name == name:
                found.append(child)
        return found^

    def child(self, node: Int, name: String) raises -> Int:
        """Return a node's first child of one name.

        Args:
            node: The node's index.
            name: The name to match.

        Returns:
            Its index, or `NO_FBX_NODE` when there is none.

        Raises:
            Error: If the index names no node.
        """
        self._check(node)
        for child in self.nodes[node].children:
            if self.nodes[child].name == name:
                return child
        return NO_FBX_NODE

    def property_count(self, node: Int) raises -> Int:
        """Return how many properties a node has.

        Args:
            node: The node's index.

        Returns:
            The count.

        Raises:
            Error: If the index names no node.
        """
        self._check(node)
        return len(self.nodes[node].properties)

    def property(self, node: Int, index: Int) raises -> FbxProperty:
        """Return one property of a node.

        Args:
            node: The node's index.
            index: Which property, from zero.

        Returns:
            A copy of the property.

        Raises:
            Error: If the index names no node or no property, or the
                property's kind is none of the six there are.
        """
        self._check(node)
        ref found = self.nodes[node].properties
        if index < 0 or index >= len(found):
            raise Error(
                "FBX: "
                + self.nodes[node].name
                + " has no property "
                + String(index)
            )
        if not found[index].kind.is_valid():
            raise Error("FBX: a property of a kind that is not known")
        return found[index].copy()

    def integer(self, node: Int, index: Int) raises -> Int:
        """Return a property as a whole number.

        Args:
            node: The node's index.
            index: Which property.

        Returns:
            The number.

        Raises:
            Error: If the property is not a number, or has a fraction.
        """
        var found = self.property(node, index)
        if found.kind == FBX_INTEGER:
            return found.integer
        var value = self.number(node, index)
        if value != Float64(Int(value)):
            raise Error(
                "FBX: a whole number was expected, not " + String(value)
            )
        return Int(value)

    def number(self, node: Int, index: Int) raises -> Float64:
        """Return a property as a number.

        Args:
            node: The node's index.
            index: Which property.

        Returns:
            The number.

        Raises:
            Error: If the property is not a number.
        """
        var found = self.property(node, index)
        if found.kind == FBX_INTEGER:
            return Float64(found.integer)
        if found.kind != FBX_NUMBER:
            raise Error(
                "FBX: a number was expected in " + self.nodes[node].name
            )
        return found.number

    def string(self, node: Int, index: Int) raises -> String:
        """Return a property as a string.

        Args:
            node: The node's index.
            index: Which property.

        Returns:
            The text.

        Raises:
            Error: If the property is not a string.
        """
        var found = self.property(node, index)
        if found.kind != FBX_STRING:
            raise Error(
                "FBX: a string was expected in " + self.nodes[node].name
            )
        return found.text

    def numbers(self, node: Int) raises -> List[Float64]:
        """Return a node's values as numbers: its one array property, or
        every property when they are single numbers.

        Args:
            node: The node's index.

        Returns:
            The numbers.

        Raises:
            Error: If the index names no node, or a property is a string,
                raw bytes, or an array beside other properties.
        """
        self._check(node)
        var count = len(self.nodes[node].properties)
        if count == 1:
            var only = self.property(node, 0)
            if only.kind == FBX_NUMBERS:
                return only.numbers.copy()
            if only.kind == FBX_INTEGERS:
                var out = List[Float64]()
                for value in only.integers:
                    out.append(Float64(value))
                return out^
        var out = List[Float64]()
        for index in range(count):
            out.append(self.number(node, index))
        return out^

    def integers(self, node: Int) raises -> List[Int]:
        """Return a node's values as whole numbers, as `numbers` finds
        them.

        Args:
            node: The node's index.

        Returns:
            The numbers.

        Raises:
            Error: If `numbers` refuses the node, or a value has a
                fraction.
        """
        self._check(node)
        if len(self.nodes[node].properties) == 1:
            var only = self.property(node, 0)
            if only.kind == FBX_INTEGERS:
                return only.integers.copy()
        var out = List[Int]()
        for value in self.numbers(node):
            if value != Float64(Int(value)):
                raise Error(
                    "FBX: a whole number was expected, not " + String(value)
                )
            out.append(Int(value))
        return out^


def object_name(name: String, format: FbxFormat) raises -> String:
    """Return an object's name as three.js reads it: after `Class::` in
    an ASCII file, and as kept in a binary one, whose `Name\\x00\\x01Class`
    was already cut at the zero byte.

    Args:
        name: The object's second property.
        format: Which form the file is written in.

    Returns:
        The name.

    Raises:
        Error: If `format` is none of `FBX_ASCII` and `FBX_BINARY`.
    """
    if not format.is_valid():
        raise Error("FBX: a format that is neither ASCII nor binary")
    if format == FBX_BINARY:
        return name
    # three.js strips `^(\w+)::`: a word of letters, digits or `_`.
    var cut = name.find("::")
    if cut <= 0:
        return name
    # `cut` is positive here: the loop always runs.
    for byte in name.as_bytes()[:cut]:  # pragma: no branch
        if not _is_word(Int(byte)):
            return name
    return String(name[byte = cut + 2 :])


def _is_word(byte: Int) -> Bool:
    """Return True for a byte of `\\w`: a letter, a digit or `_`."""
    return (
        (byte >= 48 and byte <= 57)
        or (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
    )


def parse_fbx(bytes: List[UInt8]) raises -> FbxDocument:
    """Read an FBX file, binary or ASCII, into a document.

    A file that begins with the binary magic is read as binary; any
    other is read as UTF-8 text, as three.js tells them apart.

    Args:
        bytes: The whole file.

    Returns:
        The document.

    Raises:
        Error: If the file is too old or malformed; see the module.
    """
    var magic = BINARY_MAGIC.as_bytes()
    var binary = len(bytes) >= len(magic)
    if binary:
        for index in range(len(magic)):  # pragma: no branch
            if bytes[index] != magic[index]:
                binary = False
    if binary:
        var reader = _BinaryReader(bytes)
        return reader.read()
    return parse_fbx_text(String(unsafe_from_utf8=bytes))


def parse_fbx_text(text: String) raises -> FbxDocument:
    """Read an ASCII FBX file into a document.

    Args:
        text: The whole file.

    Returns:
        The document.

    Raises:
        Error: If the text names no `FBXVersion`, names one below 7000,
            or is malformed; see the module.
    """
    # three.js finds the version with `/FBXVersion: (\d+)/` over the whole
    # text, before it reads anything else.
    var at = text.find("FBXVersion: ")
    if at < 0:
        raise Error("FBX: the file names no FBXVersion")
    var digits = String()
    for byte in text.as_bytes()[at + 12 :]:
        if byte < 48 or byte > 57:
            break
        digits += chr(Int(byte))
    if digits == "":
        raise Error("FBX: FBXVersion is not a number")
    var version = Int(digits)
    if version < MIN_ASCII_VERSION:
        raise Error("FBX: an ASCII file older than 7000: " + digits)
    var bytes = List[UInt8]()
    # The text holds `FBXVersion: `: the loop always runs.
    for byte in text.as_bytes():  # pragma: no branch
        bytes.append(byte)
    var reader = _TextReader(bytes^)
    var document = FbxDocument(FBX_ASCII)
    document.version = version
    reader.nodes(document, 0, 0)
    return document^


struct _TextReader(Movable):
    """The ASCII reader's cursor over the bytes."""

    var bytes: List[UInt8]
    var at: Int

    def __init__(out self, var bytes: List[UInt8]):
        self.bytes = bytes^
        self.at = 0

    def where(self) -> String:
        """Return the prefix of an error: the line the cursor is on."""
        var line = 1
        for index in range(min(self.at, len(self.bytes))):
            if self.bytes[index] == 10:
                line += 1
        return "FBX line " + String(line) + ": "

    def peek(self) -> Int:
        """Return the byte under the cursor, or -1 past the end."""
        if self.at >= len(self.bytes):
            return -1
        return Int(self.bytes[self.at])

    def skip_blank(mut self, lines: Bool):
        """Step over spaces and tabs, and comments from `;` to the end of
        the line; with `lines`, over line ends too."""
        while True:
            var byte = self.peek()
            if byte == 59:
                while self.peek() >= 0 and self.peek() != 10:
                    self.at += 1
            elif byte == 32 or byte == 9 or byte == 13:
                self.at += 1
            elif byte == 10 and lines:
                self.at += 1
            else:
                return

    def nodes(
        mut self, mut document: FbxDocument, parent: Int, depth: Int
    ) raises:
        """Read nodes into `parent` until its `}`, or the end of the text
        at the top.

        Args:
            document: Where the nodes go.
            parent: The node they belong to.
            depth: How deep `parent` sits; zero for the root.

        Raises:
            Error: If a node is malformed, a `{` is not closed, or a `}`
                closes nothing.
        """
        if depth >= MAX_FBX_DEPTH:
            raise Error(self.where() + "nested too deep")
        while True:
            self.skip_blank(True)
            var byte = self.peek()
            if byte == 125:
                if depth == 0:
                    raise Error(self.where() + "a '}' that closes nothing")
                self.at += 1
                return
            if byte < 0:
                if depth > 0:
                    raise Error(self.where() + "a '{' is not closed")
                return
            self.node(document, parent, depth)

    def node(
        mut self, mut document: FbxDocument, parent: Int, depth: Int
    ) raises:
        """Read one node: its name, its properties and its children."""
        var name = List[UInt8]()
        while self.peek() >= 0 and self.peek() != 58:
            var byte = self.peek()
            if byte == 10 or byte == 123 or byte == 125 or byte == 44:
                break
            name.append(UInt8(byte))
            self.at += 1
        if self.peek() != 58:
            raise Error(self.where() + "expected 'Name:'")
        self.at += 1
        document.nodes.append(
            FbxNode(String(String(unsafe_from_utf8=name).strip()))
        )
        var index = len(document.nodes) - 1
        document.nodes[parent].children.append(index)
        var declared = self.properties(document, index)
        self.skip_blank(False)
        if self.peek() == 123:
            self.at += 1
            self.nodes(document, index, depth + 1)
        if declared >= 0:
            self.fold_array(document, index, declared)

    def fold_array(
        mut self, mut document: FbxDocument, index: Int, declared: Int
    ) raises:
        """Make a `*count { a: ... }` node's `a` its one array property."""
        var values = FbxProperty(FBX_INTEGERS)
        var holder = document.child(index, "a")
        if holder != NO_FBX_NODE:
            var whole = True
            for held in document.nodes[holder].properties:
                if held.kind != FBX_INTEGER:
                    whole = False
            if whole:
                values.integers = document.integers(holder)
            else:
                values = FbxProperty(FBX_NUMBERS)
                values.numbers = document.numbers(holder)
            var kept = List[Int]()
            # The node holds `a` at least: the loop always runs.
            for child in document.nodes[index].children:  # pragma: no branch
                if child != holder:
                    kept.append(child)
            document.nodes[index].children = kept^
        var count = len(values.integers) + len(values.numbers)
        if count != declared:
            raise Error(
                self.where()
                + document.nodes[index].name
                + " declares "
                + String(declared)
                + " values and holds "
                + String(count)
            )
        document.nodes[index].properties.append(values^)

    def properties(
        mut self, mut document: FbxDocument, index: Int
    ) raises -> Int:
        """Read a node's properties, up to the end of its line or its `{`.

        A line that ends in `,` goes on to the next line, as an array
        written over many lines does.

        Returns:
            The count a `*count` declared, or -1 when there is none.
        """
        var declared = -1
        var continued = False
        while True:
            self.skip_blank(False)
            var byte = self.peek()
            if byte == 10 and continued:
                self.at += 1
                continue
            if byte < 0 or byte == 10 or byte == 123 or byte == 125:
                return declared
            if byte == 44:
                self.at += 1
                continued = True
                continue
            continued = False
            if byte == 34:
                document.nodes[index].properties.append(
                    string_property(self.quoted())
                )
                continue
            var token = self.bare()
            if token.startswith("*"):
                try:
                    declared = Int(String(token[byte=1:]))
                except:
                    raise Error(self.where() + "a malformed array count")
                continue
            document.nodes[index].properties.append(_scalar(token^))

    def quoted(mut self) raises -> String:
        """Read a quoted string, as written: FBX has no escapes."""
        self.at += 1
        var out = List[UInt8]()
        while self.peek() != 34:
            if self.peek() < 0:
                raise Error(self.where() + "a string is not closed")
            out.append(self.bytes[self.at])
            self.at += 1
        self.at += 1
        return String(unsafe_from_utf8=out)

    def bare(mut self) -> String:
        """Read an unquoted value: up to a comma, a brace, white space or
        a comment."""
        var out = List[UInt8]()
        while True:
            var byte = self.peek()
            if (
                byte < 0
                or byte == 44
                or byte == 123
                or byte == 125
                or byte == 59
                or byte == 32
                or byte == 9
                or byte == 10
                or byte == 13
            ):
                return String(unsafe_from_utf8=out)
            out.append(UInt8(byte))
            self.at += 1


def _scalar(var token: String) -> FbxProperty:
    """Return an unquoted value as a whole number, a number, or a bare
    word such as `Y` or `T`, which is kept as a string."""
    try:
        return integer_property(Int(token))
    except:
        pass
    try:
        return number_property(Float64(token))
    except:
        return string_property(token^)


def _le(bytes: List[UInt8], at: Int, count: Int) -> UInt64:
    """Return `count` bytes at `at` as a little-endian unsigned number."""
    var value = UInt64(0)
    for index in range(count):  # pragma: no branch
        value |= UInt64(bytes[at + index]) << UInt64(8 * index)
    return value


def _signed(value: UInt64, bits: Int) -> Int:
    """Return an unsigned number of `bits` bits as the signed number it
    stores in two's complement."""
    var raw = Int(value)
    if bits < 64 and raw >= (1 << (bits - 1)):
        raw -= 1 << bits
    return raw


struct _BinaryReader(Movable):
    """The binary reader's cursor over the bytes."""

    var bytes: List[UInt8]
    var at: Int
    var version: Int

    def __init__(out self, bytes: List[UInt8]):
        self.bytes = bytes.copy()
        self.at = 0
        self.version = 0

    def where(self) -> String:
        """Return the prefix of an error: where the cursor stands."""
        return "FBX at byte " + String(self.at) + ": "

    def need(self, count: Int) raises:
        """Refuse to read `count` bytes past the end of the file."""
        if self.at + count > len(self.bytes):
            raise Error(self.where() + "the file ends inside a record")

    def unsigned(mut self, count: Int) raises -> UInt64:
        """Read a little-endian unsigned number of `count` bytes."""
        self.need(count)
        var value = _le(self.bytes, self.at, count)
        self.at += count
        return value

    def take(mut self, count: Int) raises -> List[UInt8]:
        """Read `count` raw bytes."""
        self.need(count)
        var out = List[UInt8](capacity=count)
        for index in range(self.at, self.at + count):
            out.append(self.bytes[index])
        self.at += count
        return out^

    def end_of_content(self) -> Bool:
        """Return True where three.js's `endOfContent` stops: within the
        footer, which is 160 bytes and padding to sixteen."""
        var size = len(self.bytes)
        if size % 16 == 0:
            return ((self.at + 160 + 16) & ~0xF) >= size
        return self.at + 160 + 16 >= size

    def read(mut self) raises -> FbxDocument:
        """Read the header and every top-level record."""
        self.at = BINARY_VERSION_AT
        self.version = Int(self.unsigned(4))
        if self.version < MIN_BINARY_VERSION:
            raise Error(
                "FBX: a binary file older than 6400: " + String(self.version)
            )
        var document = FbxDocument(FBX_BINARY)
        document.version = self.version
        while not self.end_of_content():
            self.record(document, 0, 1)
        return document^

    def record(
        mut self, mut document: FbxDocument, parent: Int, depth: Int
    ) raises:
        """Read one record and its children into `parent`. A record whose
        end offset is zero is the null record that ends a list, and adds
        nothing."""
        if depth > MAX_FBX_DEPTH:
            raise Error(self.where() + "nested too deep")
        var size = 4
        if self.version >= WIDE_RECORD_VERSION:
            size = 8
        var end = Int(self.unsigned(size))
        var count = Int(self.unsigned(size))
        _ = self.unsigned(size)
        var length = Int(self.unsigned(1))
        var name = String(unsafe_from_utf8=self.take(length))
        if end == 0:
            return
        if end < self.at or end > len(self.bytes):
            raise Error(self.where() + "a record ends outside the file")
        document.nodes.append(FbxNode(name^))
        var index = len(document.nodes) - 1
        document.nodes[parent].children.append(index)
        for _ in range(count):
            document.nodes[index].properties.append(self.property())
        while self.at < end:
            self.record(document, index, depth + 1)
        if self.at != end:
            raise Error(self.where() + "a record's children run past its end")

    def property(mut self) raises -> FbxProperty:
        """Read one typed property."""
        var code = Int(self.unsigned(1))
        if code == 89:
            return integer_property(_signed(self.unsigned(2), 16))
        if code == 67:
            return integer_property(Int(self.unsigned(1)))
        if code == 73:
            return integer_property(_signed(self.unsigned(4), 32))
        if code == 76:
            return integer_property(_signed(self.unsigned(8), 64))
        if code == 70:
            return number_property(
                Float64(bitcast[DType.float32](UInt32(self.unsigned(4))))
            )
        if code == 68:
            return number_property(bitcast[DType.float64](self.unsigned(8)))
        if code == 83:
            var text = self.take(Int(self.unsigned(4)))
            # three.js's `getString` stops at the first zero byte.
            var cut = List[UInt8]()
            for byte in text:
                if byte == 0:
                    break
                cut.append(byte)
            return string_property(String(unsafe_from_utf8=cut))
        if code == 82:
            var raw = FbxProperty(FBX_BYTES)
            raw.bytes = self.take(Int(self.unsigned(4)))
            return raw^
        return self.array(code)

    def array(mut self, code: Int) raises -> FbxProperty:
        """Read an array property: `f`, `d`, `l`, `i`, `b` or `c`."""
        var width: Int
        if code == 102 or code == 105:
            width = 4
        elif code == 100 or code == 108:
            width = 8
        elif code == 98 or code == 99:
            width = 1
        else:
            raise Error(self.where() + "a property type that is not known")
        var count = Int(self.unsigned(4))
        var encoding = Int(self.unsigned(4))
        var stored = Int(self.unsigned(4))
        var data: List[UInt8]
        if encoding == 0:
            data = self.take(count * width)
        elif encoding == 1:
            data = zlib_inflate(self.take(stored), count * width)
            if len(data) != count * width:
                raise Error(self.where() + "a zlib array of the wrong length")
        else:
            raise Error(self.where() + "an array encoding that is not 0 or 1")
        if code == 102 or code == 100:
            var out = FbxProperty(FBX_NUMBERS)
            for index in range(count):
                var bits = _le(data, index * width, width)
                if width == 4:
                    out.numbers.append(
                        Float64(bitcast[DType.float32](UInt32(bits)))
                    )
                else:
                    out.numbers.append(bitcast[DType.float64](bits))
            return out^
        var out = FbxProperty(FBX_INTEGERS)
        for index in range(count):
            out.integers.append(
                _signed(_le(data, index * width, width), width * 8)
            )
        return out^
