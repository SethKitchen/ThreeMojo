# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""XML: the text a Collada file is written in, read into a tree of
elements.

Mojo's standard library has no XML reader, and three.js's `ColladaLoader`
leans on the browser's `DOMParser`, so this is a small reader of the part
of XML 1.0 a model file uses: elements, attributes, character data, the
five named entities and numeric character references, CDATA sections,
comments, processing instructions, and a document type declaration, which
is skipped. A file that is not well formed is refused with the byte it
went wrong at, as `DOMParser` refuses it with a `parsererror`: a tag that
is not closed, a closing tag that names another element, an attribute
given twice, an entity that is not known, text after the root element.

**One arena, as `loaders.json` has one.** Every element is an
`XmlElement` in one `List`, and an element names its children by index.
The root element is element zero. `XmlDocument` reads the tree by index.

**What is kept.** An element keeps its name as written, prefix and all,
its attributes in file order, its child elements in file order, and its
character data: the text directly inside it, CDATA included, with the
entities resolved and every line ending made a line feed, as XML asks.
Comments and processing instructions are dropped.

**What is not read.** A document type declaration is stepped over whole,
so an entity it declares is not known and is refused where it is used.
Namespaces are not resolved: `a:b` is an element named `a:b`. The text is
taken to be UTF-8 and is not checked.
"""

# What `XmlDocument.child` returns when there is no such child, and what
# the root element's parent is.
comptime NO_ELEMENT = -1
# How deep an element can sit inside others. A file nested past this is
# refused, since the loaders that read the tree walk it by recursion.
comptime MAX_XML_DEPTH = 256


struct XmlElement(Copyable, Movable):
    """One element: its name, its attributes, its children and its text."""

    var name: String
    # The attributes, one name and one value per entry, in file order.
    var attribute_names: List[String]
    var attribute_values: List[String]
    # The child elements, as indices into the document, in file order.
    var children: List[Int]
    # The character data directly inside, in file order, entities
    # resolved.
    var text: String
    # The enclosing element, or `NO_ELEMENT` for the root.
    var parent: Int

    def __init__(out self, var name: String, parent: Int):
        """Start an element with no attributes, children or text.

        Args:
            name: Its name, as written.
            parent: The enclosing element's index, or `NO_ELEMENT`.
        """
        self.name = name^
        self.attribute_names = List[String]()
        self.attribute_values = List[String]()
        self.children = List[Int]()
        self.text = String()
        self.parent = parent


struct XmlDocument(Movable):
    """A parsed XML text: every element in one list, the root at zero."""

    var elements: List[XmlElement]

    def __init__(out self):
        """Start with no elements."""
        self.elements = List[XmlElement]()

    def root(self) -> Int:
        """Return the root element's index."""
        return 0

    def count(self) -> Int:
        """Return how many elements the document has."""
        return len(self.elements)

    def _check(self, element: Int) raises:
        """Refuse an index that names no element."""
        if element < 0 or element >= len(self.elements):
            raise Error("XML: no element at index " + String(element))

    def name(self, element: Int) raises -> String:
        """Return an element's name, as written.

        Args:
            element: The element's index.

        Returns:
            Its name.

        Raises:
            Error: If the index names no element.
        """
        self._check(element)
        return self.elements[element].name

    def parent(self, element: Int) raises -> Int:
        """Return the element that encloses another.

        Args:
            element: The element's index.

        Returns:
            The enclosing element's index, or `NO_ELEMENT` for the root.

        Raises:
            Error: If the index names no element.
        """
        self._check(element)
        return self.elements[element].parent

    def has_attribute(self, element: Int, key: String) raises -> Bool:
        """Return True if an element has an attribute.

        Args:
            element: The element's index.
            key: The attribute's name.

        Returns:
            Whether the attribute is there.

        Raises:
            Error: If the index names no element.
        """
        self._check(element)
        for name in self.elements[element].attribute_names:
            if name == key:
                return True
        return False

    def attribute(
        self, element: Int, key: String, default: String = ""
    ) raises -> String:
        """Return an attribute's value, or a default when it is absent.

        Args:
            element: The element's index.
            key: The attribute's name.
            default: What to return when the element has no such
                attribute.

        Returns:
            The value, entities resolved.

        Raises:
            Error: If the index names no element.
        """
        self._check(element)
        ref found = self.elements[element]
        for index in range(len(found.attribute_names)):
            if found.attribute_names[index] == key:
                return found.attribute_values[index]
        return default

    def children(self, element: Int) raises -> List[Int]:
        """Return an element's child elements.

        Args:
            element: The element's index.

        Returns:
            Their indices, in file order.

        Raises:
            Error: If the index names no element.
        """
        self._check(element)
        return self.elements[element].children.copy()

    def children_named(self, element: Int, name: String) raises -> List[Int]:
        """Return an element's child elements of one name.

        Args:
            element: The element's index.
            name: The name to match, as written.

        Returns:
            Their indices, in file order.

        Raises:
            Error: If the index names no element.
        """
        self._check(element)
        var found = List[Int]()
        for child in self.elements[element].children:
            if self.elements[child].name == name:
                found.append(child)
        return found^

    def child(self, element: Int, name: String) raises -> Int:
        """Return an element's first child element of one name.

        Args:
            element: The element's index.
            name: The name to match, as written.

        Returns:
            Its index, or `NO_ELEMENT` when there is none.

        Raises:
            Error: If the index names no element.
        """
        self._check(element)
        for child in self.elements[element].children:
            if self.elements[child].name == name:
                return child
        return NO_ELEMENT

    def text(self, element: Int) raises -> String:
        """Return the character data directly inside an element.

        Args:
            element: The element's index.

        Returns:
            The text, entities resolved. Empty for an element with none.

        Raises:
            Error: If the index names no element.
        """
        self._check(element)
        return self.elements[element].text

    def text_content(self, element: Int) raises -> String:
        """Return all the character data inside an element: its own text,
        then each child's text content, in order.

        The DOM's `textContent` interleaves an element's own text with its
        children's in file order. A model file never mixes the two, so the
        element's own text comes first here.

        Args:
            element: The element's index.

        Returns:
            The text.

        Raises:
            Error: If the index names no element.
        """
        self._check(element)
        var out = self.elements[element].text
        for child in self.elements[element].children:
            out += self.text_content(child)
        return out^


def parse_xml(text: String) raises -> XmlDocument:
    """Read an XML text into a document.

    Args:
        text: The whole text, in UTF-8, with or without a byte order mark.

    Returns:
        The document: every element, the root at zero.

    Raises:
        Error: If the text is not well formed: no root element or text
            after it, a name, tag, attribute, comment, CDATA section,
            processing instruction or document type declaration that is
            malformed or not closed, a closing tag that does not match,
            an attribute given twice, an entity that is not known or a
            character reference that names no character, or elements
            nested deeper than `MAX_XML_DEPTH`.
    """
    var bytes = List[UInt8]()
    for byte in text.as_bytes():
        bytes.append(byte)
    var parser = _Parser(bytes^)
    var document = XmlDocument()
    if parser.starts_with("\ufeff"):
        parser.at += 3
    parser.misc(True)
    if parser.peek() != 60:
        raise Error(parser.where() + "no root element")
    parser.elements(document)
    parser.misc(False)
    if not parser.done():
        raise Error(parser.where() + "text after the root element")
    return document^


def _is_name_start(byte: Int) -> Bool:
    """Return True if a byte can begin a name: a letter, `_`, `:`, or any
    byte of a multibyte character."""
    return (
        (byte >= 65 and byte <= 90)
        or (byte >= 97 and byte <= 122)
        or byte == 95
        or byte == 58
        or byte >= 128
    )


def _is_name_byte(byte: Int) -> Bool:
    """Return True if a byte can continue a name: what can begin one, a
    digit, `-` or `.`."""
    return (
        _is_name_start(byte)
        or (byte >= 48 and byte <= 57)
        or byte == 45
        or byte == 46
    )


def _is_space(byte: Int) -> Bool:
    """Return True for the four bytes XML counts as white space."""
    return byte == 32 or byte == 9 or byte == 10 or byte == 13


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


def _is_character(point: Int) -> Bool:
    """Return True if a character reference names a character XML allows:
    not zero, not a surrogate half, and not past Unicode."""
    return (
        point > 0 and point <= 0x10FFFF and (point < 0xD800 or point > 0xDFFF)
    )


struct _Parser(Movable):
    """The reader's cursor over the bytes."""

    var bytes: List[UInt8]
    var at: Int

    def __init__(out self, var bytes: List[UInt8]):
        self.bytes = bytes^
        self.at = 0

    def where(self) -> String:
        """Return the prefix of an error: where the cursor stands."""
        return "XML at byte " + String(self.at) + ": "

    def done(self) -> Bool:
        """Return True once every byte is read."""
        return self.at >= len(self.bytes)

    def peek(self) -> Int:
        """Return the byte under the cursor, or -1 past the end."""
        if self.done():
            return -1
        return Int(self.bytes[self.at])

    def starts_with(self, word: String) -> Bool:
        """Return True if the bytes at the cursor spell `word`."""
        var expected = word.as_bytes()
        if self.at + len(expected) > len(self.bytes):
            return False
        for offset in range(len(expected)):  # pragma: no branch
            if self.bytes[self.at + offset] != expected[offset]:
                return False
        return True

    def skip_space(mut self) -> Bool:
        """Step over white space and return True if there was any."""
        var start = self.at
        while _is_space(self.peek()):
            self.at += 1
        return self.at > start

    def skip_past(mut self, end: String, what: String) raises:
        """Step past the next `end`, refusing a text that has none.

        Args:
            end: The bytes that close what is being skipped.
            what: What is being skipped, for the error.

        Raises:
            Error: If the text ends first.
        """
        while not self.starts_with(end):
            if self.done():
                raise Error(self.where() + what + " is not closed")
            self.at += 1
        self.at += end.byte_length()

    def expect(mut self, byte: Int, what: String) raises:
        """Step over one byte, refusing any other.

        Args:
            byte: The byte that must be next.
            what: What it is, for the error.

        Raises:
            Error: If another byte, or the end, is next.
        """
        if self.peek() != byte:
            raise Error(self.where() + "expected " + what)
        self.at += 1

    def name(mut self) raises -> String:
        """Read a name at the cursor."""
        if not _is_name_start(self.peek()):
            raise Error(self.where() + "expected a name")
        var out = List[UInt8]()
        while _is_name_byte(self.peek()):
            out.append(self.bytes[self.at])
            self.at += 1
        return String(unsafe_from_utf8=out)

    def misc(mut self, prolog: Bool) raises:
        """Step over white space, comments and processing instructions
        outside the root element, and before it a document type
        declaration.

        Args:
            prolog: True before the root element, where a document type
                declaration can stand.

        Raises:
            Error: If one of them is not closed, or a document type
                declaration comes after the root element.
        """
        while True:
            _ = self.skip_space()
            if self.starts_with("<?"):
                self.skip_past("?>", "a processing instruction")
            elif self.starts_with("<!--"):
                self.skip_past("-->", "a comment")
            elif self.starts_with("<!DOCTYPE"):
                if not prolog:
                    raise Error(
                        self.where()
                        + "a document type declaration after the root"
                    )
                self.doctype()
            else:
                return

    def doctype(mut self) raises:
        """Step over a document type declaration, internal subset and
        all."""
        var depth = 0
        while True:
            var byte = self.peek()
            if byte < 0:
                raise Error(
                    self.where() + "a document type declaration is not closed"
                )
            self.at += 1
            if byte == 91:
                depth += 1
            elif byte == 93:
                depth -= 1
            elif byte == 62 and depth <= 0:
                return

    def reference(mut self, mut out: List[UInt8]) raises:
        """Read an entity or a character reference at the cursor and
        append what it stands for."""
        var start = self.at
        self.at += 1
        var body = List[UInt8]()
        while self.peek() != 59:
            if self.peek() < 0 or len(body) > 10:
                self.at = start
                raise Error(self.where() + "a reference is not closed by ';'")
            body.append(self.bytes[self.at])
            self.at += 1
        self.at += 1
        var word = String(unsafe_from_utf8=body)
        if word == "lt":
            out.append(60)
        elif word == "gt":
            out.append(62)
        elif word == "amp":
            out.append(38)
        elif word == "quot":
            out.append(34)
        elif word == "apos":
            out.append(39)
        elif word.startswith("#"):
            var point = self.code_point(word, start)
            _append_utf8(out, point)
        else:
            self.at = start
            raise Error(self.where() + "an entity that is not known: " + word)

    def code_point(mut self, word: String, start: Int) raises -> Int:
        """Return the character a `#nn` or `#xhh` reference names.

        Args:
            word: The reference between `&` and `;`.
            start: Where it began, for the error.

        Returns:
            The code point.

        Raises:
            Error: If the digits are not digits, or name no character.
        """
        var point: Int
        try:
            if word.startswith("#x"):
                point = atol(String(word[byte=2:]), base=16)
            else:
                point = atol(String(word[byte=1:]))
        except:
            self.at = start
            raise Error(self.where() + "a character reference is malformed")
        if not _is_character(point):
            self.at = start
            raise Error(self.where() + "a character reference names nothing")
        return point

    def attribute_value(mut self) raises -> String:
        """Read a quoted attribute value, resolving references and making
        each white space byte a space, as XML normalizes it."""
        var quote = self.peek()
        if quote != 34 and quote != 39:
            raise Error(self.where() + "expected a quoted attribute value")
        self.at += 1
        var out = List[UInt8]()
        while True:
            var byte = self.peek()
            if byte < 0:
                raise Error(self.where() + "an attribute value is not closed")
            if byte == quote:
                self.at += 1
                return String(unsafe_from_utf8=out)
            if byte == 60:
                raise Error(self.where() + "'<' inside an attribute value")
            if byte == 38:
                self.reference(out)
            elif _is_space(byte):
                out.append(32)
                self.at += 1
            else:
                out.append(UInt8(byte))
                self.at += 1

    def start_tag(
        mut self,
        mut document: XmlDocument,
        mut open: List[Int],
        mut texts: List[List[UInt8]],
    ) raises:
        """Read a start tag or an empty-element tag and add its element.

        Args:
            document: Where the element goes.
            open: The elements whose end tags are still to come, the
                innermost last. The new element goes on it unless its tag
                closes itself.
            texts: The character data read so far for each open element.

        Raises:
            Error: If the tag is malformed, an attribute is given twice,
                or the element is nested too deep.
        """
        if len(open) >= MAX_XML_DEPTH:
            raise Error(self.where() + "nested too deep")
        self.at += 1
        var parent = NO_ELEMENT
        if len(open) > 0:
            parent = open[len(open) - 1]
        var element = XmlElement(self.name(), parent)
        var closed = False
        while True:
            var spaced = self.skip_space()
            var byte = self.peek()
            if byte == 47:
                self.at += 1
                self.expect(62, "'>' after '/'")
                closed = True
                break
            if byte == 62:
                self.at += 1
                break
            if not spaced:
                raise Error(self.where() + "expected a space, '>' or '/>'")
            var key = self.name()
            _ = self.skip_space()
            self.expect(61, "'=' after an attribute name")
            _ = self.skip_space()
            var value = self.attribute_value()
            for seen in element.attribute_names:
                if seen == key:
                    raise Error(
                        self.where() + "an attribute given twice: " + key
                    )
            element.attribute_names.append(key^)
            element.attribute_values.append(value^)
        document.elements.append(element^)
        var index = len(document.elements) - 1
        if parent != NO_ELEMENT:
            document.elements[parent].children.append(index)
        if not closed:
            open.append(index)
            texts.append(List[UInt8]())

    def end_tag(
        mut self,
        mut document: XmlDocument,
        mut open: List[Int],
        mut texts: List[List[UInt8]],
    ) raises:
        """Read an end tag, which must close the innermost open element,
        and give that element its text."""
        self.at += 2
        var name = self.name()
        var element = open[len(open) - 1]
        if name != document.elements[element].name:
            raise Error(
                self.where()
                + "</"
                + name
                + "> closes <"
                + document.elements[element].name
                + ">"
            )
        _ = self.skip_space()
        self.expect(62, "'>' to end a closing tag")
        document.elements[element].text = String(unsafe_from_utf8=texts.pop())
        _ = open.pop()

    def elements(mut self, mut document: XmlDocument) raises:
        """Read the root element and everything inside it, without
        recursion: `open` holds the elements not yet closed."""
        var open = List[Int]()
        var texts = List[List[UInt8]]()
        self.start_tag(document, open, texts)
        while len(open) > 0:
            var byte = self.peek()
            if byte < 0:
                raise Error(
                    self.where()
                    + "<"
                    + document.elements[open[len(open) - 1]].name
                    + "> is not closed"
                )
            ref text = texts[len(texts) - 1]
            if byte == 38:
                self.reference(text)
            elif byte == 13:
                # A carriage return, alone or before a line feed, is one
                # line feed, as XML normalizes a line ending.
                text.append(10)
                self.at += 1
                if self.peek() == 10:
                    self.at += 1
            elif byte != 60:
                text.append(UInt8(byte))
                self.at += 1
            elif self.starts_with("</"):
                self.end_tag(document, open, texts)
            elif self.starts_with("<!--"):
                self.skip_past("-->", "a comment")
            elif self.starts_with("<![CDATA["):
                self.at += 9
                while not self.starts_with("]]>"):
                    if self.done():
                        raise Error(
                            self.where() + "a CDATA section is not closed"
                        )
                    text.append(self.bytes[self.at])
                    self.at += 1
                self.at += 3
            elif self.starts_with("<?"):
                self.skip_past("?>", "a processing instruction")
            else:
                self.start_tag(document, open, texts)
