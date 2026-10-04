# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""STEP physical files, ISO 10303-21: the text form of IFC.

A file has a header section and a data section. Each data entry is an
entity instance: `#12=IFCWALL('2Xh...',$,'wall 3',...);`. An attribute
value is an integer, a real, a string, an enumeration such as `.ELEMENT.`,
a reference such as `#12`, a list in parentheses, a typed value such as
`IFCLABEL('x')`, `$` for unset or `*` for derived.

`StepFile` holds the values in one arena: each value is a `StepValue` with
a kind, and a list or a typed value names its children by index. `parse`
reads the text, refusing malformed input with the line of the error.
`StepFile.write` writes the text back. A real is written with the shortest
digits that read back to the same number, so values round-trip exactly.

Strings decode the escapes of the standard: `''` for a quote, `\\\\` for a
backslash, `\\X\\hh` for a byte of ISO 8859-1, `\\X2\\hhhh...\\X0\\` for UTF-16
and `\\X4\\hhhhhhhh...\\X0\\` for UTF-32 code points. The writer escapes
every non-ASCII character as `\\X2\\` or `\\X4\\`.
"""

from std.math import isfinite


@fieldwise_init
struct StepKind(Equatable, ImplicitlyCopyable, Writable):
    """What a STEP value is."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this names one of the nine kinds.

        Returns:
            Whether the value is 0 to 8.
        """
        return self.value >= 0 and self.value <= 8


comptime INTEGER = StepKind(0)
comptime REAL = StepKind(1)
comptime STRING = StepKind(2)
comptime ENUMERATION = StepKind(3)
comptime REFERENCE = StepKind(4)
comptime LIST = StepKind(5)
comptime TYPED = StepKind(6)
comptime UNSET = StepKind(7)
comptime DERIVED = StepKind(8)


struct StepValue(Copyable, Movable):
    """One attribute value.

    An integer or a reference keeps its number in `integer`; a real keeps
    `real`; a string keeps `text`; an enumeration keeps its name, without
    dots, in `text`; a typed value keeps its type name in `text` and its
    one child in `children`; a list keeps its children.
    """

    var kind: StepKind
    var integer: Int
    var real: Float64
    var text: String
    var children: List[Int]

    def __init__(
        out self,
        kind: StepKind,
        integer: Int,
        real: Float64,
        var text: String,
        var children: List[Int],
    ):
        """Create a value. `StepFile` methods make these.

        Args:
            kind: What it is.
            integer: The number of an integer or a reference.
            real: The number of a real.
            text: The text of a string, an enumeration or a type name.
            children: The values of a list, or the one of a typed value.
        """
        self.kind = kind
        self.integer = integer
        self.real = real
        self.text = text^
        self.children = children^


struct StepEntity(Copyable, Movable):
    """One instance: its number, its type name and its attribute values."""

    var id: Int
    var name: String
    var arguments: List[Int]

    def __init__(out self, id: Int, var name: String, var arguments: List[Int]):
        """Create an entity instance.

        Args:
            id: Its instance number, as in `#12`. Zero for a header entry.
            name: Its type name, in capitals.
            arguments: Its attribute values, as indices into the arena.
        """
        self.id = id
        self.name = name^
        self.arguments = arguments^


struct StepFile(Movable):
    """A STEP physical file: header entries, data entities and the values
    they hold."""

    var values: List[StepValue]
    var header: List[StepEntity]
    var entities: List[StepEntity]
    var _index: Dict[Int, Int]

    def __init__(out self):
        """Create an empty file."""
        self.values = List[StepValue]()
        self.header = List[StepEntity]()
        self.entities = List[StepEntity]()
        self._index = Dict[Int, Int]()

    # --- values -----------------------------------------------------------

    def _push(mut self, var value: StepValue) -> Int:
        self.values.append(value^)
        return len(self.values) - 1

    def integer(mut self, value: Int) -> Int:
        """Add an integer value.

        Args:
            value: The integer.

        Returns:
            Its index.
        """
        return self._push(StepValue(INTEGER, value, 0, "", List[Int]()))

    def real(mut self, value: Float64) raises -> Int:
        """Add a real value.

        Args:
            value: The real. It must be finite.

        Returns:
            Its index.

        Raises:
            Error: If the real is not finite.
        """
        if not isfinite(value):
            raise Error("A STEP real must be finite")
        return self._push(StepValue(REAL, 0, value, "", List[Int]()))

    def string(mut self, text: String) -> Int:
        """Add a string value.

        Args:
            text: The text.

        Returns:
            Its index.
        """
        return self._push(StepValue(STRING, 0, 0, text, List[Int]()))

    def enumeration(mut self, name: String) -> Int:
        """Add an enumeration value.

        Args:
            name: Its name, without dots, such as `ELEMENT`.

        Returns:
            Its index.
        """
        return self._push(StepValue(ENUMERATION, 0, 0, name, List[Int]()))

    def reference(mut self, id: Int) -> Int:
        """Add a reference to an entity instance.

        Args:
            id: The instance number.

        Returns:
            Its index.
        """
        return self._push(StepValue(REFERENCE, id, 0, "", List[Int]()))

    def list(mut self, var children: List[Int]) -> Int:
        """Add a list value.

        Args:
            children: The indices of its items.

        Returns:
            Its index.
        """
        return self._push(StepValue(LIST, 0, 0, "", children^))

    def typed(mut self, name: String, child: Int) -> Int:
        """Add a typed value, such as `IFCLABEL('x')`.

        Args:
            name: The type name.
            child: The index of the value it wraps.

        Returns:
            Its index.
        """
        return self._push(StepValue(TYPED, 0, 0, name, [child]))

    def unset(mut self) -> Int:
        """Add an unset value, `$`.

        Returns:
            Its index.
        """
        return self._push(StepValue(UNSET, 0, 0, "", List[Int]()))

    def derived(mut self) -> Int:
        """Add a derived value, `*`.

        Returns:
            Its index.
        """
        return self._push(StepValue(DERIVED, 0, 0, "", List[Int]()))

    def reals(mut self, numbers: List[Float64]) raises -> Int:
        """Add a list of reals.

        Args:
            numbers: The reals. Each must be finite.

        Returns:
            The list's index.

        Raises:
            Error: If a real is not finite.
        """
        var children = List[Int]()
        for i in range(len(numbers)):
            children.append(self.real(numbers[i]))
        return self.list(children^)

    def references(mut self, ids: List[Int]) -> Int:
        """Add a list of references.

        Args:
            ids: The instance numbers.

        Returns:
            The list's index.
        """
        var children = List[Int]()
        for i in range(len(ids)):
            children.append(self.reference(ids[i]))
        return self.list(children^)

    # --- entities ---------------------------------------------------------

    def add(mut self, var name: String, var arguments: List[Int]) -> Int:
        """Add a data entity with the next instance number.

        Args:
            name: Its type name, in capitals.
            arguments: Its attribute values.

        Returns:
            Its instance number.
        """
        var id = len(self.entities) + 1
        while id in self._index:
            id += 1
        self._index[id] = len(self.entities)
        self.entities.append(StepEntity(id, name^, arguments^))
        return id

    def add_header(mut self, var name: String, var arguments: List[Int]):
        """Add a header entry, such as `FILE_SCHEMA`.

        Args:
            name: Its name, in capitals.
            arguments: Its values.
        """
        self.header.append(StepEntity(0, name^, arguments^))

    def has(self, id: Int) -> Bool:
        """Return True if an instance number names an entity.

        Args:
            id: The instance number.

        Returns:
            Whether the file has it.
        """
        return id in self._index

    def entity(self, id: Int) raises -> StepEntity:
        """Return a copy of the entity with an instance number.

        Args:
            id: The instance number.

        Returns:
            The entity.

        Raises:
            Error: If no entity has that number.
        """
        if id not in self._index:
            raise Error(String("No STEP entity #", id))
        return self.entities[self._index[id]].copy()

    def all_of(self, name: String) -> List[Int]:
        """Return the instance numbers of every entity of a type, in order.

        Args:
            name: The type name, in capitals.

        Returns:
            The instance numbers.
        """
        var out = List[Int]()
        for i in range(len(self.entities)):
            if self.entities[i].name == name:
                out.append(self.entities[i].id)
        return out^

    # --- reading attributes ---------------------------------------------------

    def argument(self, id: Int, position: Int) raises -> Int:
        """Return the index of one attribute value of an entity.

        Args:
            id: The instance number.
            position: The attribute's position, from zero.

        Returns:
            The value's index.

        Raises:
            Error: If there is no such entity or attribute.
        """
        var e = self.entity(id)
        if position < 0 or position >= len(e.arguments):
            raise Error(
                String("STEP entity #", id, " has no attribute ", position)
            )
        return e.arguments[position]

    def kind_of(self, value: Int) -> StepKind:
        """Return the kind of a value. The index must be in range.

        Args:
            value: The value's index.

        Returns:
            Its kind.
        """
        return self.values[value].kind

    def _expect(self, value: Int, kind: StepKind, what: String) raises:
        if self.values[value].kind != kind:
            raise Error(String("A STEP value is not ", what))

    def as_integer(self, value: Int) raises -> Int:
        """Return an integer value.

        Args:
            value: The value's index.

        Returns:
            The integer.

        Raises:
            Error: If the value is not an integer.
        """
        self._expect(value, INTEGER, "an integer")
        return self.values[value].integer

    def as_real(self, value: Int) raises -> Float64:
        """Return a real value, or an integer as a real.

        Args:
            value: The value's index.

        Returns:
            The number.

        Raises:
            Error: If the value is neither a real nor an integer.
        """
        ref v = self.values[value]
        if v.kind == INTEGER:
            return Float64(v.integer)
        self._expect(value, REAL, "a real")
        return v.real

    def as_string(self, value: Int) raises -> String:
        """Return a string value.

        Args:
            value: The value's index.

        Returns:
            The text.

        Raises:
            Error: If the value is not a string.
        """
        self._expect(value, STRING, "a string")
        return self.values[value].text

    def as_enumeration(self, value: Int) raises -> String:
        """Return an enumeration's name, without dots.

        Args:
            value: The value's index.

        Returns:
            The name.

        Raises:
            Error: If the value is not an enumeration.
        """
        self._expect(value, ENUMERATION, "an enumeration")
        return self.values[value].text

    def as_reference(self, value: Int) raises -> Int:
        """Return the instance number a reference names.

        Args:
            value: The value's index.

        Returns:
            The instance number.

        Raises:
            Error: If the value is not a reference.
        """
        self._expect(value, REFERENCE, "a reference")
        return self.values[value].integer

    def as_list(self, value: Int) raises -> List[Int]:
        """Return the items of a list value.

        Args:
            value: The value's index.

        Returns:
            The indices of its items.

        Raises:
            Error: If the value is not a list.
        """
        self._expect(value, LIST, "a list")
        return self.values[value].children.copy()

    def untyped(self, value: Int) -> Int:
        """Return the value a typed value wraps, or the value itself.

        Args:
            value: The value's index.

        Returns:
            The index of the wrapped value.
        """
        var v = value
        while self.values[v].kind == TYPED:
            v = self.values[v].children[0]
        return v

    # --- writing ----------------------------------------------------------

    def _write_value(self, value: Int, mut out: String) raises:
        ref v = self.values[value]
        if v.kind == INTEGER:
            out += String(v.integer)
        elif v.kind == REAL:
            out += format_real(v.real)
        elif v.kind == STRING:
            out += "'"
            out += encode_string(v.text)
            out += "'"
        elif v.kind == ENUMERATION:
            out += "."
            out += v.text
            out += "."
        elif v.kind == REFERENCE:
            out += "#"
            out += String(v.integer)
        elif v.kind == LIST:
            out += "("
            for i in range(len(v.children)):
                if i > 0:
                    out += ","
                self._write_value(v.children[i], out)
            out += ")"
        elif v.kind == TYPED:
            out += v.text
            out += "("
            self._write_value(v.children[0], out)
            out += ")"
        elif v.kind == UNSET:
            out += "$"
        else:
            out += "*"

    def _write_arguments(self, arguments: List[Int], mut out: String) raises:
        out += "("
        for i in range(len(arguments)):
            if i > 0:
                out += ","
            self._write_value(arguments[i], out)
        out += ")"

    def write(self) raises -> String:
        """Return the file as STEP text.

        Returns:
            The text, from `ISO-10303-21;` to `END-ISO-10303-21;`.

        Raises:
            Error: If a real cannot be written.
        """
        var out = String("ISO-10303-21;\nHEADER;\n")
        for i in range(len(self.header)):
            out += self.header[i].name
            self._write_arguments(self.header[i].arguments, out)
            out += ";\n"
        out += "ENDSEC;\nDATA;\n"
        for i in range(len(self.entities)):
            ref e = self.entities[i]
            out += "#"
            out += String(e.id)
            out += "="
            out += e.name
            self._write_arguments(e.arguments, out)
            out += ";\n"
        out += "ENDSEC;\nEND-ISO-10303-21;\n"
        return out^


def format_real(value: Float64) raises -> String:
    """Return a real in STEP form: the shortest digits that read back, with
    a decimal point and a capital E.

    Args:
        value: The real. It must be finite.

    Returns:
        The text, such as `1.`, `0.25` or `1.E-05`.

    Raises:
        Error: If the real is not finite.
    """
    if not isfinite(value):
        raise Error("A STEP real must be finite")
    var parts = String(value).split("e")
    var mantissa = String(parts[0])
    var exponent = String("")
    if len(parts) > 1:
        exponent = String("E") + String(parts[1])
    if mantissa.find(".") < 0:
        mantissa += "."
    elif mantissa.endswith(".0"):
        var trimmed = String(mantissa.removesuffix("0"))
        mantissa = trimmed^
    return mantissa + exponent


def _hex_digit(value: Int) -> String:
    """Return one uppercase hexadecimal digit."""
    var digits = "0123456789ABCDEF"
    return String(digits[byte=value])


def _hex(value: Int, width: Int) -> String:
    """Return a number as uppercase hexadecimal of a fixed width."""
    var out = String("")
    var shift = 4 * (width - 1)
    while shift >= 0:
        out += _hex_digit((value >> shift) & 15)
        shift -= 4
    return out^


def encode_string(text: String) -> String:
    """Return text with the escapes of a STEP string, without the quotes.

    Args:
        text: The text.

    Returns:
        The escaped text: quotes doubled, backslashes doubled and every
        code point outside printable ASCII written as `\\X2\\` (or `\\X4\\`
        beyond the basic plane).
    """
    var out = String("")
    for cp in text.codepoints():
        var c = Int(cp)
        if c == 39:
            out += "''"
        elif c == 92:
            out += "\\\\"
        elif c >= 32 and c < 127:
            out += chr(c)
        elif c < 0x10000:
            out += "\\X2\\"
            out += _hex(c, 4)
            out += "\\X0\\"
        else:
            out += "\\X4\\"
            out += _hex(c, 8)
            out += "\\X0\\"
    return out^


struct _Reader:
    """A cursor over the bytes of a STEP file."""

    var data: List[UInt8]
    var at: Int
    var line: Int

    def __init__(out self, text: String):
        self.data = List[UInt8](text.as_bytes())
        self.at = 0
        self.line = 1

    def fail(self, message: String) -> Error:
        return Error(String("STEP line ", self.line, ": ", message))

    def peek(self) -> Int:
        return Int(self.data[self.at]) if self.at < len(self.data) else -1

    def skip_space(mut self) raises:
        """Skip blanks, line breaks and comments."""
        while self.at < len(self.data):
            var c = Int(self.data[self.at])
            if c == 10:
                self.line += 1
                self.at += 1
            elif c == 32 or c == 9 or c == 13:
                self.at += 1
            elif (
                c == 47
                and self.at + 1 < len(self.data)
                and Int(self.data[self.at + 1]) == 42
            ):
                self.at += 2
                var closed = False
                while self.at + 1 < len(self.data):
                    if Int(self.data[self.at]) == 10:
                        self.line += 1
                    if (
                        Int(self.data[self.at]) == 42
                        and Int(self.data[self.at + 1]) == 47
                    ):
                        self.at += 2
                        closed = True
                        break
                    self.at += 1
                if not closed:
                    raise self.fail("an unclosed comment")
            else:
                return

    def expect(mut self, c: Int, what: String) raises:
        self.skip_space()
        if self.peek() != c:
            raise self.fail(String("expected ", what))
        self.at += 1

    def keyword(mut self) raises -> String:
        """Read a name of letters, digits, underscores and hyphens."""
        self.skip_space()
        var start = self.at
        while self.at < len(self.data):
            var c = Int(self.data[self.at])
            var letter = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
            var digit = c >= 48 and c <= 57
            if letter or digit or c == 95 or c == 45:
                self.at += 1
            else:
                break
        if self.at == start:
            raise self.fail("expected a name")
        var out = String("")
        for i in range(start, self.at):  # pragma: no branch
            out += chr(Int(self.data[i]))
        return out.upper()

    def number_text(mut self) -> String:
        var start = self.at
        while self.at < len(self.data):
            var c = Int(self.data[self.at])
            var digit = c >= 48 and c <= 57
            if digit or c == 43 or c == 45 or c == 46 or c == 69 or c == 101:
                self.at += 1
            else:
                break
        var out = String("")
        for i in range(start, self.at):
            out += chr(Int(self.data[i]))
        return out^

    def hex_value(mut self, count: Int) raises -> Int:
        var value = 0
        for _ in range(count):  # pragma: no branch
            if self.at >= len(self.data):
                raise self.fail("a short hexadecimal escape")
            var c = Int(self.data[self.at])
            var digit: Int
            if c >= 48 and c <= 57:
                digit = c - 48
            elif c >= 65 and c <= 70:
                digit = c - 55
            elif c >= 97 and c <= 102:
                digit = c - 87
            else:
                raise self.fail("a bad hexadecimal digit")
            value = value * 16 + digit
            self.at += 1
        return value

    def starts(self, text: String) -> Bool:
        var bytes = text.as_bytes()
        if self.at + len(bytes) > len(self.data):
            return False
        for i in range(len(bytes)):  # pragma: no branch
            if self.data[self.at + i] != bytes[i]:
                return False
        return True

    def string(mut self) raises -> String:
        """Read a quoted string, decoding its escapes."""
        self.at += 1
        var start_line = self.line
        var out = String("")
        while True:
            if self.at >= len(self.data):
                self.line = start_line
                raise self.fail("an unclosed string")
            var c = Int(self.data[self.at])
            if c == 39:
                if (
                    self.at + 1 < len(self.data)
                    and Int(self.data[self.at + 1]) == 39
                ):
                    out += "'"
                    self.at += 2
                    continue
                self.at += 1
                return out^
            if c == 92:
                if self.starts("\\\\"):
                    out += "\\"
                    self.at += 2
                elif self.starts("\\X2\\"):
                    self.at += 4
                    while not self.starts("\\X0\\"):
                        out += chr(self.hex_value(4))
                    self.at += 4
                elif self.starts("\\X4\\"):
                    self.at += 4
                    while not self.starts("\\X0\\"):
                        out += chr(self.hex_value(8))
                    self.at += 4
                elif self.starts("\\X\\"):
                    self.at += 3
                    out += chr(self.hex_value(2))
                else:
                    raise self.fail("an unknown string escape")
                continue
            if c == 10:
                self.line += 1
            out += chr(c)
            self.at += 1


def _parse_value(mut reader: _Reader, mut file: StepFile) raises -> Int:
    """Read one attribute value into the arena and return its index."""
    reader.skip_space()
    var c = reader.peek()
    if c == 36:
        reader.at += 1
        return file.unset()
    if c == 42:
        reader.at += 1
        return file.derived()
    if c == 39:
        return file.string(reader.string())
    if c == 35:
        reader.at += 1
        var digits = reader.number_text()
        if digits.byte_length() == 0:
            raise reader.fail("expected an instance number")
        return file.reference(atol(digits))
    if c == 46:
        reader.at += 1
        var name = reader.keyword()
        reader.expect(46, "a dot after an enumeration")
        return file.enumeration(name)
    if c == 40:
        reader.at += 1
        var children = List[Int]()
        reader.skip_space()
        if reader.peek() == 41:
            reader.at += 1
            return file.list(children^)
        while True:
            children.append(_parse_value(reader, file))
            reader.skip_space()
            var next = reader.peek()
            reader.at += 1
            if next == 41:
                return file.list(children^)
            if next != 44:
                raise reader.fail("expected a comma or a closing parenthesis")
    var digit = c >= 48 and c <= 57
    if digit or c == 45 or c == 43:
        var text = reader.number_text()
        if text.find(".") >= 0 or text.find("E") >= 0 or text.find("e") >= 0:
            return file.real(atof(text))
        return file.integer(atol(text))
    var letter = (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
    if letter:
        var name = reader.keyword()
        reader.expect(40, "a parenthesis after a type name")
        var child = _parse_value(reader, file)
        reader.expect(41, "a closing parenthesis after a typed value")
        return file.typed(name, child)
    raise reader.fail("expected a value")


def _parse_arguments(
    mut reader: _Reader, mut file: StepFile
) raises -> List[Int]:
    """Read a parenthesized list of attribute values."""
    var list_index = _parse_value(reader, file)
    if file.kind_of(list_index) != LIST:
        raise reader.fail("expected attributes in parentheses")
    return file.as_list(list_index)


def parse(text: String) raises -> StepFile:
    """Read a STEP physical file.

    Args:
        text: The file's text.

    Returns:
        Its header entries, entities and values.

    Raises:
        Error: If the text is not a well-formed STEP file, giving the line:
            a missing section, a bad value, an unclosed string or comment,
            or a repeated instance number.
    """
    var reader = _Reader(text)
    var file = StepFile()
    reader.skip_space()
    if reader.keyword() != "ISO-10303-21":
        raise reader.fail("expected ISO-10303-21")
    reader.expect(59, "a semicolon")
    if reader.keyword() != "HEADER":
        raise reader.fail("expected HEADER")
    reader.expect(59, "a semicolon")
    while True:
        var name = reader.keyword()
        if name == "ENDSEC":
            reader.expect(59, "a semicolon")
            break
        var arguments = _parse_arguments(reader, file)
        reader.expect(59, "a semicolon")
        file.add_header(name, arguments^)
    if reader.keyword() != "DATA":
        raise reader.fail("expected DATA")
    reader.expect(59, "a semicolon")
    while True:
        reader.skip_space()
        if reader.peek() != 35:
            if reader.keyword() != "ENDSEC":
                raise reader.fail("expected an entity or ENDSEC")
            reader.expect(59, "a semicolon")
            break
        reader.at += 1
        var digits = reader.number_text()
        if digits.byte_length() == 0:
            raise reader.fail("expected an instance number")
        var id = atol(digits)
        reader.expect(61, "an equals sign")
        var name = reader.keyword()
        var arguments = _parse_arguments(reader, file)
        reader.expect(59, "a semicolon")
        if file.has(id):
            raise reader.fail(String("a repeated instance #", id))
        file._index[id] = len(file.entities)
        file.entities.append(StepEntity(id, name, arguments^))
    if reader.keyword() != "END-ISO-10303-21":
        raise reader.fail("expected END-ISO-10303-21")
    reader.expect(59, "a semicolon")
    return file^
