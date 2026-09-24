# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""The text of a VRML 2.0 file as a tree, from three.js
`examples/jsm/loaders/VRMLLoader.js`: its chevrotain lexer, parser and
visitor.

`lex_vrml` cuts the text into tokens as three.js's lexer does. It tries
each token kind in three.js's order, and the first that matches wins.
White space and commas are skipped, and so is a comment from `#` to the
end of the line. A keyword or a node name that an identifier continues,
such as `DEFAULT` or `Boxes`, is an identifier, as chevrotain's
`longer_alt` makes it. An identifier with a dot in it is a route
identifier. A node name is the first of three.js's list that the text
starts with, so `ColorInterpolator` is an identifier: `Color` comes
first in the list.

`parse_vrml_tree` reads the tokens by three.js's grammar: a version
line, one or more nodes, then routes. A node is an optional `DEF` name,
a node name and fields in braces. A field is an identifier and one or
more values, or a list of values in brackets. A list holds no `TRUE` or
`FALSE`.

**How values are grouped.** three.js's visitor collects a field's
values by kind, not in file order: the nodes, then the `USE` names, the
strings, the numbers, the hex numbers, the `TRUE`s, the `FALSE`s and
the `NULL`s. The field's kind is the last of these kinds that it has.
This keeps both. A string keeps its escapes, and loses each `"` and
`'`, as three.js's `replace( /'|"/g, '' )` does.

**Where this port differs.** three.js reads a number too big for a
double as infinity; this refuses it. A lexing or parsing error is
refused with the place where it happened. three.js logs chevrotain's
errors and then throws.
"""

from loaders.js_number import js_parse_float
from std.math import isfinite


@fieldwise_init
struct VrmlTokenKind(Equatable, ImplicitlyCopyable, Writable):
    """What a token is, as a type rather than a bare int.

    `parse_vrml_tree` refuses a token whose kind is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the token kinds."""
        return self.value >= VRML_VERSION.value and (
            self.value <= VRML_RIGHT_CURLY.value
        )


comptime VRML_VERSION = VrmlTokenKind(0)
comptime VRML_NODE_NAME = VrmlTokenKind(1)
comptime VRML_DEF = VrmlTokenKind(2)
comptime VRML_USE = VrmlTokenKind(3)
comptime VRML_ROUTE = VrmlTokenKind(4)
comptime VRML_TO = VrmlTokenKind(5)
comptime VRML_TRUE = VrmlTokenKind(6)
comptime VRML_FALSE = VrmlTokenKind(7)
comptime VRML_NULL = VrmlTokenKind(8)
comptime VRML_IDENTIFIER = VrmlTokenKind(9)
comptime VRML_ROUTE_IDENTIFIER = VrmlTokenKind(10)
comptime VRML_STRING = VrmlTokenKind(11)
comptime VRML_HEX = VrmlTokenKind(12)
comptime VRML_NUMBER = VrmlTokenKind(13)
comptime VRML_LEFT_SQUARE = VrmlTokenKind(14)
comptime VRML_RIGHT_SQUARE = VrmlTokenKind(15)
comptime VRML_LEFT_CURLY = VrmlTokenKind(16)
comptime VRML_RIGHT_CURLY = VrmlTokenKind(17)


@fieldwise_init
struct VrmlValueKind(Equatable, ImplicitlyCopyable, Writable):
    """What a field value is, three.js's field `type`, as a type rather
    than a bare int.

    `vrml_scene` in `loaders.vrml` refuses a kind that is not valid.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the value kinds."""
        return self.value >= VRML_NODE_VALUE.value and (
            self.value <= VRML_NO_VALUE.value
        )


# A node, written in place: three.js's `'node'`.
comptime VRML_NODE_VALUE = VrmlValueKind(0)
# A `USE` of a node named by `DEF`: three.js's `'use'`.
comptime VRML_USE_VALUE = VrmlValueKind(1)
comptime VRML_STRING_VALUE = VrmlValueKind(2)
comptime VRML_NUMBER_VALUE = VrmlValueKind(3)
# A hex number such as `0xFF0000`, kept as its text: three.js's `'hex'`.
comptime VRML_HEX_VALUE = VrmlValueKind(4)
comptime VRML_BOOLEAN_VALUE = VrmlValueKind(5)
comptime VRML_NULL_VALUE = VrmlValueKind(6)
# The kind of a field with no values, three.js's `null`.
comptime VRML_NO_VALUE = VrmlValueKind(7)

# three.js's `nodeTypes`, in its order: the lexer takes the first that
# the text starts with.
comptime _NODE_TYPES: List[String] = [
    "Anchor",
    "Billboard",
    "Collision",
    "Group",
    "Transform",
    "Inline",
    "LOD",
    "Switch",
    "AudioClip",
    "DirectionalLight",
    "PointLight",
    "Script",
    "Shape",
    "Sound",
    "SpotLight",
    "WorldInfo",
    "CylinderSensor",
    "PlaneSensor",
    "ProximitySensor",
    "SphereSensor",
    "TimeSensor",
    "TouchSensor",
    "VisibilitySensor",
    "Box",
    "Cone",
    "Cylinder",
    "ElevationGrid",
    "Extrusion",
    "IndexedFaceSet",
    "IndexedLineSet",
    "PointSet",
    "Sphere",
    "Color",
    "Coordinate",
    "Normal",
    "TextureCoordinate",
    "Appearance",
    "FontStyle",
    "ImageTexture",
    "Material",
    "MovieTexture",
    "PixelTexture",
    "TextureTransform",
    "ColorInterpolator",
    "CoordinateInterpolator",
    "NormalInterpolator",
    "OrientationInterpolator",
    "PositionInterpolator",
    "ScalarInterpolator",
    "Background",
    "Fog",
    "NavigationInfo",
    "Viewpoint",
    "Text",
]


struct VrmlToken(Copyable, Movable):
    """One token: its kind, its text and the byte where it starts."""

    var kind: VrmlTokenKind
    var image: String
    var offset: Int

    def __init__(out self, kind: VrmlTokenKind, var image: String, offset: Int):
        """Hold a token.

        Args:
            kind: What it is.
            image: Its text.
            offset: The byte where it starts.
        """
        self.kind = kind
        self.image = image^
        self.offset = offset


def _is_digit(byte: UInt8) -> Bool:
    """Return True for `[0-9]`."""
    return byte >= 48 and byte <= 57


def _is_hex_digit(byte: UInt8) -> Bool:
    """Return True for `[0-9a-fA-F]`."""
    var lower = byte | 32
    return _is_digit(byte) or (lower >= 97 and lower <= 102)


def _excluded(byte: UInt8) -> Bool:
    """Return True for a byte that no identifier holds: a control, a
    space, or one of `"'#+,.[]\\{}`."""
    return (
        byte <= 0x20
        or byte == 0x22
        or byte == 0x27
        or byte == 0x23
        or byte == 0x2B
        or byte == 0x2C
        or byte == 0x2E
        or byte == 0x5B
        or byte == 0x5D
        or byte == 0x5C
        or byte == 0x7B
        or byte == 0x7D
    )


def _starts_identifier(byte: UInt8) -> Bool:
    """Return True for a byte that can start an identifier: not a digit,
    not `-`, and not excluded."""
    return not (_excluded(byte) or _is_digit(byte) or byte == 0x2D)


def _identifier_length(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the length of three.js's `Identifier` at `at`, or zero."""
    if not _starts_identifier(bytes[at]):
        return 0
    var end = at + 1
    while _identifier_byte(bytes, end):
        end += 1
    return end - at


def _identifier_byte(bytes: Span[UInt8, _], at: Int) -> Bool:
    """Return True if an identifier goes on at `at`."""
    return at < len(bytes) and not _excluded(bytes[at])


def _route_byte(bytes: Span[UInt8, _], at: Int) -> Bool:
    """Return True if a part of a route identifier goes on at `at`."""
    return _identifier_byte(bytes, at) and bytes[at] != 0x2D


def _route_length(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the length of three.js's `RouteIdentifier` at `at`, or zero.
    The caller has found an identifier start there."""
    var end = at + 1
    while _route_byte(bytes, end):
        end += 1
    var dot = end < len(bytes) and bytes[end] == 0x2E
    if not dot:
        return 0
    end += 1
    var second = end < len(bytes) and _starts_identifier(bytes[end])
    if not second:
        return 0
    end += 1
    while _route_byte(bytes, end):
        end += 1
    return end - at


def _space_length(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the length of one character of JavaScript's `[ ,\\s]` at
    `at`, or zero."""
    var b = bytes[at]
    var ascii = b == 0x20 or b == 0x2C or (b >= 0x09 and b <= 0x0D)
    if ascii:
        return 1
    var code = _code_point(bytes, at)
    var wide = (
        code == 0xA0
        or code == 0x1680
        or (code >= 0x2000 and code <= 0x200A)
        or code == 0x2028
        or code == 0x2029
        or code == 0x202F
        or code == 0x205F
        or code == 0x3000
        or code == 0xFEFF
    )
    if not wide:
        return 0
    return 2 if code < 0x800 else 3


def _code_point(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the code point of a two- or three-byte UTF-8 sequence at
    `at`, or -1 for any other byte."""
    var b = Int(bytes[at])
    var two = b >= 0xC0 and b < 0xE0 and at + 1 < len(bytes)
    if two:
        return ((b & 0x1F) << 6) | (Int(bytes[at + 1]) & 0x3F)
    var three = b >= 0xE0 and b < 0xF0 and at + 2 < len(bytes)
    if three:
        return (
            ((b & 0x0F) << 12)
            | ((Int(bytes[at + 1]) & 0x3F) << 6)
            | (Int(bytes[at + 2]) & 0x3F)
        )
    return -1


def _line_end(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return where JavaScript's `.*` stops: before a line feed, a carriage
    return, a line separator or a paragraph separator."""
    var end = at
    while end < len(bytes):
        var b = bytes[end]
        if b == 0x0A or b == 0x0D:
            return end
        var separator = (
            b == 0xE2
            and end + 2 < len(bytes)
            and bytes[end + 1] == 0x80
            and (bytes[end + 2] == 0xA8 or bytes[end + 2] == 0xA9)
        )
        if separator:
            return end
        end += 1
    return end


def _starts_with(bytes: Span[UInt8, _], at: Int, word: String) -> Bool:
    """Return True if the text at `at` starts with `word`."""
    var w = word.as_bytes()
    if at + len(w) > len(bytes):
        return False
    # Each word has letters. The loop always runs.
    for i in range(len(w)):  # pragma: no branch
        if bytes[at + i] != w[i]:
            return False
    return True


def _string_length(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the length of three.js's `StringLiteral` at `at`, or zero."""
    var end = at + 1
    while end < len(bytes):
        var b = bytes[end]
        if b == 0x22:
            return end + 1 - at
        if b == 0x0A or b == 0x0D:
            return 0
        if b == 0x5C:
            var escape = _escape_length(bytes, end)
            if escape == 0:
                return 0
            end += escape
        else:
            end += 1
    return 0


def _escape_length(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the length of an escape at `at`: `\\` and one of
    `bfnrtv"\\/`, or `\\u` and four hex digits. Zero for none."""
    if at + 1 >= len(bytes):
        return 0
    var b = bytes[at + 1]
    var simple = (
        b == 0x62
        or b == 0x66
        or b == 0x6E
        or b == 0x72
        or b == 0x74
        or b == 0x76
        or b == 0x22
        or b == 0x5C
        or b == 0x2F
    )
    if simple:
        return 2
    if b != 0x75:
        return 0
    # Four hex digits. The loop always runs.
    for k in range(2, 6):  # pragma: no branch
        var hex = at + k < len(bytes) and _is_hex_digit(bytes[at + k])
        if not hex:
            return 0
    return 6


def _digits(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return where a run of digits from `at` ends."""
    var end = at
    while end < len(bytes) and _is_digit(bytes[end]):
        end += 1
    return end


def _hex_length(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the length of three.js's `HexLiteral` at `at`, or zero."""
    var prefix = (
        bytes[at] == 0x30
        and at + 2 < len(bytes)
        and (bytes[at + 1] | 32) == 0x78
        and _is_hex_digit(bytes[at + 2])
    )
    if not prefix:
        return 0
    var end = at + 2
    while end < len(bytes) and _is_hex_digit(bytes[end]):
        end += 1
    return end - at


def _number_length(bytes: Span[UInt8, _], at: Int) -> Int:
    """Return the length of three.js's `NumberLiteral` at `at`, or zero:
    `[-+]?[0-9]*\\.?[0-9]+([eE][-+]?[0-9]+)?`."""
    var end = at
    if bytes[end] == 0x2B or bytes[end] == 0x2D:
        end += 1
    var whole = _digits(bytes, end)
    var fraction = (
        whole < len(bytes)
        and bytes[whole] == 0x2E
        and whole + 1 < len(bytes)
        and _is_digit(bytes[whole + 1])
    )
    if fraction:
        end = _digits(bytes, whole + 1)
    elif whole == end:
        return 0
    else:
        end = whole
    var exponent = end < len(bytes) and (bytes[end] | 32) == 0x65
    if exponent:
        var digits_at = end + 1
        var signed = digits_at < len(bytes) and (
            bytes[digits_at] == 0x2B or bytes[digits_at] == 0x2D
        )
        if signed:
            digits_at += 1
        var after = _digits(bytes, digits_at)
        if after > digits_at:
            end = after
    return end - at


def _keyword(bytes: Span[UInt8, _], at: Int, mut kind: VrmlTokenKind) -> Int:
    """Return the length of a node name or a keyword at `at`, and set its
    kind; zero for none."""
    # The list is not empty. The loop always runs.
    for name in materialize[_NODE_TYPES]():  # pragma: no branch
        if _starts_with(bytes, at, name):
            kind = VRML_NODE_NAME
            return name.byte_length()
    var words: List[String] = ["DEF", "USE", "ROUTE", "TO"]
    var kinds: List[VrmlTokenKind] = [VRML_DEF, VRML_USE, VRML_ROUTE, VRML_TO]
    # Four words. The loop always runs.
    for w in range(len(words)):  # pragma: no branch
        if _starts_with(bytes, at, words[w]):
            kind = kinds[w]
            return words[w].byte_length()
    return 0


def _literal(bytes: Span[UInt8, _], at: Int, mut kind: VrmlTokenKind) -> Int:
    """Return the length of `TRUE`, `FALSE` or `NULL` at `at`, and set its
    kind; zero for none."""
    if _starts_with(bytes, at, "TRUE"):
        kind = VRML_TRUE
        return 4
    if _starts_with(bytes, at, "FALSE"):
        kind = VRML_FALSE
        return 5
    if _starts_with(bytes, at, "NULL"):
        kind = VRML_NULL
        return 4
    return 0


def _punctuation(byte: UInt8) -> VrmlTokenKind:
    """Return the kind of a bracket or a brace, or a kind that is not
    valid."""
    if byte == 0x5B:
        return VRML_LEFT_SQUARE
    if byte == 0x5D:
        return VRML_RIGHT_SQUARE
    if byte == 0x7B:
        return VRML_LEFT_CURLY
    if byte == 0x7D:
        return VRML_RIGHT_CURLY
    return VrmlTokenKind(-1)


def lex_vrml(text: String) raises -> List[VrmlToken]:
    """Cut the text of a VRML file into tokens, three.js's `VRMLLexer`.

    Args:
        text: The whole file.

    Returns:
        The tokens, with white space and comments left out.

    Raises:
        Error: At the first byte that starts no token, as chevrotain
            reports a lexing error.
    """
    var bytes = text.as_bytes()
    var tokens = List[VrmlToken]()
    var at = 0
    while at < len(bytes):
        var space = _space_length(bytes, at)
        if space > 0:
            at += space
            continue
        var kind = VrmlTokenKind(-1)
        var length = _keyword(bytes, at, kind)
        if length > 0:
            # chevrotain's `longer_alt`: an identifier that runs on wins.
            var identifier = _identifier_length(bytes, at)
            if identifier > length:
                kind = VRML_IDENTIFIER
                length = identifier
        else:
            length = _literal(bytes, at, kind)
        if length == 0:
            if _starts_with(bytes, at, "#VRML"):
                kind = VRML_VERSION
                length = _line_end(bytes, at) - at
            else:
                length = _identifier_length(bytes, at)
                if length > 0:
                    kind = VRML_IDENTIFIER
                    var route = _route_length(bytes, at)
                    if route > length:
                        kind = VRML_ROUTE_IDENTIFIER
                        length = route
        if length == 0:
            length = _other(bytes, at, kind)
        if length < 0:
            # A comment, skipped as chevrotain skips it.
            at = _line_end(bytes, at)
            continue
        if length == 0:
            raise Error(
                "VRML: unexpected character at byte "
                + String(at)
                + " of the file"
            )
        tokens.append(
            VrmlToken(kind, String(text[byte = at : at + length]), at)
        )
        at += length
    return tokens^


def _other(bytes: Span[UInt8, _], at: Int, mut kind: VrmlTokenKind) -> Int:
    """Return the length of a string, a hex number, a number or a bracket
    at `at` and set its kind, -1 for a comment, or zero for none."""
    if bytes[at] == 0x22:
        kind = VRML_STRING
        return _string_length(bytes, at)
    var hex = _hex_length(bytes, at)
    if hex > 0:
        kind = VRML_HEX
        return hex
    var number = _number_length(bytes, at)
    if number > 0:
        kind = VRML_NUMBER
        return number
    kind = _punctuation(bytes[at])
    if kind.is_valid():
        return 1
    if bytes[at] == 0x23:
        return -1
    return 0


struct VrmlValue(Copyable, Movable):
    """One value of a field, one of three.js's `field.values`."""

    var kind: VrmlValueKind
    # The number of a number value.
    var number: Float64
    # A boolean value.
    var boolean: Bool
    # The text of a string or a hex number, or the name a `USE` names.
    var text: String
    # A node value, as an index into `VrmlTree.nodes`.
    var node: Int

    def __init__(out self, kind: VrmlValueKind):
        """Make an empty value of a kind.

        Args:
            kind: What it is.
        """
        self.kind = kind
        self.number = 0
        self.boolean = False
        self.text = String()
        self.node = -1


struct VrmlField(Copyable, Movable):
    """A field of a node, three.js's `{ name, type, values }`."""

    var name: String
    # The last kind of value it has, in three.js's order.
    var kind: VrmlValueKind
    # Its values, grouped by kind in three.js's order.
    var values: List[VrmlValue]

    def __init__(out self, var name: String):
        """Make a field with no values.

        Args:
            name: Its name.
        """
        self.name = name^
        self.kind = VRML_NO_VALUE
        self.values = List[VrmlValue]()


struct VrmlNode(Copyable, Movable):
    """A node, three.js's `{ name, fields, DEF }`."""

    var name: String
    # The name `DEF` gives it, or empty.
    var def_name: String
    var has_def: Bool
    var fields: List[VrmlField]

    def __init__(out self, var name: String):
        """Make a node with no fields.

        Args:
            name: Its node name, such as `Transform`.
        """
        self.name = name^
        self.def_name = String()
        self.has_def = False
        self.fields = List[VrmlField]()


struct VrmlTree(Movable):
    """What three.js's visitor gives: `{ version, nodes, routes }`."""

    var version: String
    # Every node in the file, parents before their children.
    var nodes: List[VrmlNode]
    # The nodes at the top of the file, as indices into `nodes`.
    var roots: List[Int]
    # Each `ROUTE`, as the identifiers it goes from and to.
    var route_from: List[String]
    var route_to: List[String]

    def __init__(out self):
        """Make an empty tree."""
        self.version = String()
        self.nodes = List[VrmlNode]()
        self.roots = List[Int]()
        self.route_from = List[String]()
        self.route_to = List[String]()


struct _Parser(Movable):
    """The token reader."""

    var tokens: List[VrmlToken]
    var at: Int

    def __init__(out self, var tokens: List[VrmlToken]):
        """Read from the first token."""
        self.tokens = tokens^
        self.at = 0

    def peek(self) -> VrmlTokenKind:
        """Return the kind of the next token, or a kind that is not valid
        at the end."""
        if self.at < len(self.tokens):
            return self.tokens[self.at].kind
        return VrmlTokenKind(-1)

    def where(self) -> String:
        """Return where the next token is, for an error."""
        if self.at < len(self.tokens):
            return "at byte " + String(self.tokens[self.at].offset)
        return "at the end of the file"

    def expect(mut self, kind: VrmlTokenKind, what: String) raises -> String:
        """Take a token of a kind and return its text.

        Raises:
            Error: If the next token is of another kind.
        """
        if self.peek() != kind:
            raise Error("VRML: expected " + what + " " + self.where())
        self.at += 1
        return self.tokens[self.at - 1].image

    def starts_node(self) -> Bool:
        """Return True if a node starts at the next token."""
        var kind = self.peek()
        return kind == VRML_DEF or kind == VRML_NODE_NAME

    def node(mut self, mut tree: VrmlTree) raises -> Int:
        """Read a node, three.js's `node` rule, and return its index."""
        var def_name = String()
        var has_def = False
        if self.peek() == VRML_DEF:
            self.at += 1
            if self.peek() == VRML_NODE_NAME:
                def_name = self.expect(VRML_NODE_NAME, "a name")
            else:
                def_name = self.expect(VRML_IDENTIFIER, "a name after DEF")
            has_def = True
        var name = self.expect(VRML_NODE_NAME, "a node name")
        var index = len(tree.nodes)
        tree.nodes.append(VrmlNode(name))
        tree.nodes[index].def_name = def_name^
        tree.nodes[index].has_def = has_def
        _ = self.expect(VRML_LEFT_CURLY, "`{`")
        while self.peek() == VRML_IDENTIFIER:
            var field = self.field(tree)
            tree.nodes[index].fields.append(field^)
        _ = self.expect(VRML_RIGHT_CURLY, "`}` or a field name")
        return index

    def field(mut self, mut tree: VrmlTree) raises -> VrmlField:
        """Read a field, three.js's `field` rule."""
        var field = VrmlField(self.expect(VRML_IDENTIFIER, "a field name"))
        var groups = List[List[VrmlValue]]()
        # Eight groups. The loop always runs.
        for _ in range(8):  # pragma: no branch
            groups.append(List[VrmlValue]())
        if self.peek() == VRML_LEFT_SQUARE:
            self.at += 1
            while self.value(tree, groups, False):
                pass
            _ = self.expect(VRML_RIGHT_SQUARE, "`]` or a value")
        elif not self.value(tree, groups, True):
            raise Error("VRML: expected a value " + self.where())
        else:
            while self.value(tree, groups, True):
                pass
        # three.js's order: nodes, uses, strings, numbers, hex numbers,
        # trues, falses and nulls. Trues and falses are both booleans.
        var kinds: List[VrmlValueKind] = [
            VRML_NODE_VALUE,
            VRML_USE_VALUE,
            VRML_STRING_VALUE,
            VRML_NUMBER_VALUE,
            VRML_HEX_VALUE,
            VRML_BOOLEAN_VALUE,
            VRML_BOOLEAN_VALUE,
            VRML_NULL_VALUE,
        ]
        # Eight groups. The loop always runs.
        for g in range(8):  # pragma: no branch
            if len(groups[g]) > 0:
                field.kind = kinds[g]
            for v in groups[g]:
                field.values.append(v.copy())
        return field^

    def value(
        mut self,
        mut tree: VrmlTree,
        mut groups: List[List[VrmlValue]],
        single: Bool,
    ) raises -> Bool:
        """Read one value into its group, or return False if none starts
        at the next token. A list holds no `TRUE` or `FALSE`."""
        var kind = self.peek()
        if self.starts_node():
            var value = VrmlValue(VRML_NODE_VALUE)
            value.node = self.node(tree)
            groups[0].append(value^)
            return True
        if kind == VRML_USE:
            self.at += 1
            var value = VrmlValue(VRML_USE_VALUE)
            if self.peek() == VRML_NODE_NAME:
                value.text = self.expect(VRML_NODE_NAME, "a name")
            else:
                value.text = self.expect(VRML_IDENTIFIER, "a name after USE")
            groups[1].append(value^)
            return True
        var image = (
            self.tokens[self.at].image if self.at
            < len(self.tokens) else String()
        )
        if kind == VRML_STRING:
            var value = VrmlValue(VRML_STRING_VALUE)
            value.text = image.replace('"', "").replace("'", "")
            groups[2].append(value^)
        elif kind == VRML_NUMBER:
            var value = VrmlValue(VRML_NUMBER_VALUE)
            value.number = js_parse_float(image)
            if not isfinite(value.number):
                raise Error(
                    "VRML: a number too big for a double " + self.where()
                )
            groups[3].append(value^)
        elif kind == VRML_HEX:
            var value = VrmlValue(VRML_HEX_VALUE)
            value.text = image
            groups[4].append(value^)
        elif kind == VRML_NULL:
            groups[7].append(VrmlValue(VRML_NULL_VALUE))
        else:
            var boolean = single and (kind == VRML_TRUE or kind == VRML_FALSE)
            if not boolean:
                return False
            var value = VrmlValue(VRML_BOOLEAN_VALUE)
            value.boolean = kind == VRML_TRUE
            groups[6 if kind == VRML_FALSE else 5].append(value^)
        self.at += 1
        return True


def parse_vrml_tree(var tokens: List[VrmlToken]) raises -> VrmlTree:
    """Read tokens into a tree, three.js's `VRMLParser` and its visitor.

    Args:
        tokens: What `lex_vrml` gives.

    Returns:
        The tree.

    Raises:
        Error: If a token's kind is not valid, or the tokens do not follow
            three.js's grammar, with where the error is.
    """
    for token in tokens:
        if not token.kind.is_valid():
            raise Error("VRML: a token kind that is not valid")
    var parser = _Parser(tokens^)
    var tree = VrmlTree()
    tree.version = parser.expect(VRML_VERSION, "a `#VRML` version line")
    if not parser.starts_node():
        raise Error("VRML: expected a node " + parser.where())
    while parser.starts_node():
        tree.roots.append(parser.node(tree))
    while parser.peek() == VRML_ROUTE:
        parser.at += 1
        tree.route_from.append(
            parser.expect(VRML_ROUTE_IDENTIFIER, "a route identifier")
        )
        _ = parser.expect(VRML_TO, "TO")
        tree.route_to.append(
            parser.expect(VRML_ROUTE_IDENTIFIER, "a route identifier")
        )
    if parser.at < len(parser.tokens):
        raise Error("VRML: expected the end of the file " + parser.where())
    return tree^


def parse_vrml_text(text: String) raises -> VrmlTree:
    """Lex and parse the text of a VRML file.

    Args:
        text: The whole file.

    Returns:
        The tree.

    Raises:
        Error: For anything `lex_vrml` or `parse_vrml_tree` refuses.
    """
    return parse_vrml_tree(lex_vrml(text))
