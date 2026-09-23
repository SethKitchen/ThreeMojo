# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""STL files, from three.js `examples/jsm/loaders/STLLoader.js`.

The format of 3D printers: a list of triangles, each with its own normal,
and nothing shared between them. It comes in two encodings, and
`parse_stl` tells them apart the way three.js does:

- Binary: an 80-byte header, a little-endian 32-bit face count, then 50
  bytes a face: a normal and three corners as twelve `Float32`s, and a
  16-bit attribute. A file exactly as long as its face count says is
  binary, whatever its header holds.
- ASCII: text, `solid name`, then `facet normal x y z`, `outer loop`,
  three `vertex x y z`, `endloop`, `endfacet`, and `endsolid`. A file
  that is not exactly as long as a binary one and holds `solid` in its
  first ten bytes is read as text; anything else is binary.

The geometry comes out non-indexed, as three.js's does: three corners a
face, each with the face's normal as its `normal`, since the format has
no other. A file with several solids gives one geometry, and `StlModel`
says where each solid's corners start, as three.js adds a group a solid.

Color is the binary format's, in the convention three.js reads: a header
that holds `COLOR=` and four bytes gives a default color and an alpha,
and then each face's 16-bit attribute is a color of five bits a channel,
red in the low bits, unless its top bit is set, which asks for the
default. The colors are sRGB, and are decoded to linear light into a
`color` attribute, as three.js decodes them. A binary file whose header
has no `COLOR=` has no `color` attribute, whatever its attributes hold:
most writers leave them zero, and a zero is black, not "no color".

A coordinate that is not a number or not finite as a `Float32`, a binary
file shorter than its face count says, a facet without exactly one normal
and three corners, and a keyword out of place are refused, naming the
face or the line.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from render.srgb import srgb_to_linear
from std.math import isfinite
from std.memory import bitcast
from std.pathlib import Path

# The bytes before a binary file's face count, and the face count's own.
comptime _HEADER = 80
comptime _PREAMBLE = 84
# One binary face: twelve `Float32`s and a 16-bit attribute.
comptime _FACE = 50


@fieldwise_init
struct StlSolid(Copyable, Movable):
    """One solid of an STL file: its name, and which corners of the
    geometry are its. three.js's group, a solid each."""

    # From the `solid` line; empty when the line names none, and for a
    # binary file, which has no names.
    var name: String
    # The first corner of the solid, counting the geometry's vertices.
    var start: Int
    # How many corners it has: three a face.
    var count: Int


struct StlModel(Movable):
    """Everything an STL file described: one geometry, and the solids it
    came from."""

    var geometry: BufferGeometry
    # One a solid, in file order. A binary file has one, with no name.
    var solids: List[StlSolid]
    # The alpha of a binary header's `COLOR=`, from zero to one; one when
    # the file gives none. three.js's `geometry.alpha`. The geometry has a
    # `color` attribute exactly when the header gives a color.
    var alpha: Float32

    def __init__(
        out self,
        var geometry: BufferGeometry,
        var solids: List[StlSolid],
        alpha: Float32,
    ):
        """Bundle a finished model.

        Args:
            geometry: The triangles of every solid.
            solids: Where each solid's corners are.
            alpha: The header's alpha, or one.
        """
        self.geometry = geometry^
        self.solids = solids^
        self.alpha = alpha

    def has_colors(self) -> Bool:
        """Return True if the file gave its faces colors: three.js's
        `geometry.hasColors`."""
        return self.geometry.has_attribute(String(COLOR))

    def take_geometry(mut self) -> BufferGeometry:
        """Give up the geometry, to go into a `GeometryStore`.

        A `BufferGeometry` moves and does not copy, so it is swapped out
        for an empty one.

        Returns:
            The geometry.
        """
        var taken = BufferGeometry()
        swap(self.geometry, taken)
        return taken^


def _u32(bytes: List[UInt8], at: Int) -> UInt32:
    """Return the little-endian 32-bit word at `at`, which the caller has
    checked is in the file."""
    return (
        UInt32(bytes[at])
        | (UInt32(bytes[at + 1]) << 8)
        | (UInt32(bytes[at + 2]) << 16)
        | (UInt32(bytes[at + 3]) << 24)
    )


def _holds(bytes: List[UInt8], at: Int, word: String) -> Bool:
    """Return True if the file holds `word` at byte `at`.

    Args:
        bytes: The file.
        at: Where to look.
        word: The ASCII text to look for.

    Returns:
        Whether every byte of the word is there.
    """
    var text = word.as_bytes()
    if at + len(text) > len(bytes):
        return False
    # The words looked for are never empty: the loop always runs.
    for index in range(len(text)):  # pragma: no branch
        if bytes[at + index] != text[index]:
            return False
    return True


def is_binary_stl(bytes: List[UInt8]) -> Bool:
    """Return True if a file is binary STL, as three.js's `isBinary`
    decides.

    A file exactly as long as a binary file of its face count is binary.
    Otherwise a file with `solid` at one of its first five bytes is text:
    up to five bytes of byte order mark can come first. Anything else is
    binary.

    Args:
        bytes: The file.

    Returns:
        Whether to read it as binary.
    """
    if len(bytes) >= _PREAMBLE:
        var faces = Int(_u32(bytes, _HEADER))
        if _PREAMBLE + faces * _FACE == len(bytes):
            return True
    # Five offsets: the loop always runs.
    for offset in range(5):  # pragma: no branch
        if _holds(bytes, offset, "solid"):
            return False
    return True


def _float(bytes: List[UInt8], at: Int, face: Int) raises -> Float32:
    """Return the little-endian `Float32` at `at` of a binary face.

    Args:
        bytes: The file.
        at: Where the number is.
        face: Which face, from zero, for the error.

    Returns:
        The number.

    Raises:
        Error: If it is not finite.
    """
    var value = bitcast[DType.float32](_u32(bytes, at))
    if not isfinite(value):
        raise Error(
            "STL face "
            + String(face)
            + ": a coordinate must be a finite number, and this one is "
            + String(value)
        )
    return value


def _channel(value: Int, scale: Float32) -> Float32:
    """Return one sRGB channel as a linear one.

    Args:
        value: The channel as stored.
        scale: The largest value it can have.

    Returns:
        The channel, from zero to one, in linear light.
    """
    return srgb_to_linear(Float32(value) / scale)


def _parse_binary(bytes: List[UInt8]) raises -> StlModel:
    """Read a binary STL file.

    Args:
        bytes: The file.

    Returns:
        Its model.

    Raises:
        Error: If the file is too short for its header or its face count,
            or a number in it is not finite.
    """
    if len(bytes) < _PREAMBLE:
        raise Error(
            "STL: a binary file starts with "
            + String(_PREAMBLE)
            + " bytes of header and face count, and this one has only "
            + String(len(bytes))
        )
    var faces = Int(_u32(bytes, _HEADER))
    var needed = _PREAMBLE + faces * _FACE
    if len(bytes) < needed:
        raise Error(
            "STL: the header says "
            + String(faces)
            + " faces, which take "
            + String(needed)
            + " bytes, and the file has only "
            + String(len(bytes))
        )
    # The header's default color. three.js looks at every place a
    # ten-byte `COLOR=rgba` fits and keeps the last it finds.
    var colored = False
    var default_r = Float32(0)
    var default_g = Float32(0)
    var default_b = Float32(0)
    var alpha = Float32(1)
    # Seventy places: the loop always runs.
    for at in range(_HEADER - 10):  # pragma: no branch
        if _holds(bytes, at, "COLOR="):
            colored = True
            default_r = _channel(Int(bytes[at + 6]), 255)
            default_g = _channel(Int(bytes[at + 7]), 255)
            default_b = _channel(Int(bytes[at + 8]), 255)
            alpha = Float32(Int(bytes[at + 9])) / 255
    var positions = List[Float32](capacity=faces * 9)
    var normals = List[Float32](capacity=faces * 9)
    var colors = List[Float32]()
    for face in range(faces):
        var start = _PREAMBLE + face * _FACE
        var nx = _float(bytes, start, face)
        var ny = _float(bytes, start + 4, face)
        var nz = _float(bytes, start + 8, face)
        var r = default_r
        var g = default_g
        var b = default_b
        var packed = Int(bytes[start + 48]) | (Int(bytes[start + 49]) << 8)
        if packed & 0x8000 == 0:
            r = _channel(packed & 0x1F, 31)
            g = _channel((packed >> 5) & 0x1F, 31)
            b = _channel((packed >> 10) & 0x1F, 31)
        # Three corners and three axes: both loops always run.
        for corner in range(1, 4):  # pragma: no branch
            for axis in range(3):  # pragma: no branch
                positions.append(
                    _float(bytes, start + corner * 12 + axis * 4, face)
                )
            normals.append(nx)
            normals.append(ny)
            normals.append(nz)
            if colored:
                colors.append(r)
                colors.append(g)
                colors.append(b)
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    if colored:
        geometry.set_attribute(String(COLOR), BufferAttribute(colors^, 3))
    var solids = List[StlSolid]()
    solids.append(StlSolid(String(), 0, faces * 3))
    return StlModel(geometry^, solids^, alpha)


struct _Words:
    """The words of an ASCII file, each with its line, read in order."""

    var words: List[String]
    var lines: List[Int]
    var at: Int

    def __init__(out self, text: String):
        """Split a text into words.

        Args:
            text: The whole file.
        """
        self.words = List[String]()
        self.lines = List[Int]()
        self.at = 0
        var line = 0
        # A split yields at least one piece, even of nothing: the loop
        # always runs.
        for raw in text.split("\n"):  # pragma: no branch
            line += 1
            for word in String(raw).split():
                self.words.append(String(word))
                self.lines.append(line)

    def done(self) -> Bool:
        """Return True once every word is read."""
        return self.at >= len(self.words)

    def line(self) -> Int:
        """Return the line of the word last read, or of the last word once
        every word is read."""
        return self.lines[self.at - 1]

    def next(mut self, wanted: String) raises -> String:
        """Return the next word.

        Args:
            wanted: What the word must be, for the error.

        Returns:
            The word.

        Raises:
            Error: If the file has ended.
        """
        if self.done():
            raise Error("STL: the file ends where " + wanted + " must be")
        self.at += 1
        return self.words[self.at - 1]

    def expect(mut self, word: String) raises:
        """Read the next word and refuse anything but `word`.

        Args:
            word: The keyword that must come next.

        Raises:
            Error: If the file ends, or the next word is another.
        """
        var got = self.next("`" + word + "`")
        if got != word:
            raise Error(
                _where(self.line())
                + "`"
                + word
                + "` must come here, and the file has `"
                + got
                + "`"
            )

    def number(mut self) raises -> Float32:
        """Read the next word as a coordinate.

        Read wide, then narrowed to the `Float32` a geometry holds, and
        refused if either step gives something that is not a finite
        number.

        Returns:
            The number.

        Raises:
            Error: If the file ends, or the word is not a number or not
                finite as a `Float32`.
        """
        var field = self.next("a number")
        var wide: Float64
        try:
            wide = Float64(field)
        except reason:
            raise Error(
                _where(self.line())
                + "not a number: "
                + field
                + " ("
                + String(reason)
                + ")"
            )
        var value = Float32(wide)
        if not isfinite(value):
            raise Error(
                _where(self.line())
                + "a coordinate must be a finite number: "
                + field
            )
        return value

    def rest_of_line(mut self) -> String:
        """Read the words left on the line of the word last read, and
        return them joined by single spaces: a solid's name.

        Returns:
            The name, or an empty string when the line has no more words.
        """
        var line = self.line()
        var name = String()
        while not self.done() and self.lines[self.at] == line:
            if name != "":
                name += " "
            name += self.words[self.at]
            self.at += 1
        return name^


def _where(line: Int) -> String:
    """Return the prefix an error names its line with."""
    return "STL line " + String(line) + ": "


def parse_stl_text(text: String) raises -> StlModel:
    """Read the text of an ASCII STL file into a model.

    Args:
        text: The whole file.

    Returns:
        One geometry of every solid's facets, a solid each in `solids`,
        and an alpha of one.

    Raises:
        Error: If the text has no solid, a solid is not closed or holds
            another, a keyword comes outside what holds it, a facet has
            no normal or other than three vertices, a coordinate is not a
            number or not finite, or a word is not STL at all.
    """
    var words = _Words(text)
    var positions = List[Float32]()
    var normals = List[Float32]()
    var solids = List[StlSolid]()
    var name = String()
    var start = 0
    var in_solid = False
    var in_facet = False
    var corners = 0
    var nx = Float32(0)
    var ny = Float32(0)
    var nz = Float32(0)
    while not words.done():
        var word = words.next("a keyword")
        var line = words.line()
        if word == "solid":
            if in_solid:
                raise Error(_where(line) + "a solid inside a solid")
            in_solid = True
            name = words.rest_of_line()
            start = len(positions) // 3
        elif word == "endsolid":
            if not in_solid or in_facet:
                raise Error(
                    _where(line) + "`endsolid` outside a solid, or in a facet"
                )
            # The name again, which three.js does not compare either.
            _ = words.rest_of_line()
            in_solid = False
            var count = len(positions) // 3 - start
            solids.append(StlSolid(name, start, count))
        elif word == "facet":
            if not in_solid or in_facet:
                raise Error(
                    _where(line) + "`facet` outside a solid, or in a facet"
                )
            words.expect("normal")
            nx = words.number()
            ny = words.number()
            nz = words.number()
            in_facet = True
            corners = 0
        elif (
            word == "outer"
            or word == "endloop"
            or word == "vertex"
            or word == "endfacet"
        ):
            if not in_facet:
                raise Error(_where(line) + "`" + word + "` outside a facet")
            if word == "outer":
                words.expect("loop")
            elif word == "vertex":
                if corners == 3:
                    raise Error(
                        _where(line) + "a facet has more than three vertices"
                    )
                positions.append(words.number())
                positions.append(words.number())
                positions.append(words.number())
                normals.append(nx)
                normals.append(ny)
                normals.append(nz)
                corners += 1
            elif word == "endfacet":
                if corners != 3:
                    raise Error(
                        _where(line) + "a facet has fewer than three vertices"
                    )
                in_facet = False
        else:
            raise Error(_where(line) + "a word STL does not have: " + word)
    if in_solid:
        raise Error("STL: the file ends inside a solid, before `endsolid`")
    if len(solids) == 0:
        raise Error("STL: the text has no solid")
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), BufferAttribute(positions^, 3))
    geometry.set_attribute(String(NORMAL), BufferAttribute(normals^, 3))
    return StlModel(geometry^, solids^, Float32(1))


def parse_stl(bytes: List[UInt8]) raises -> StlModel:
    """Read an STL file's bytes into a model, binary or ASCII.

    Args:
        bytes: The whole file.

    Returns:
        Its model; see `parse_stl_text` for ASCII. A binary file has one
        solid with no name, and a `color` attribute and an alpha when its
        header has `COLOR=`.

    Raises:
        Error: If a binary file is too short for its header or its face
            count, or holds a number that is not finite; if a text file
            is not UTF-8; or for anything `parse_stl_text` refuses.
    """
    if is_binary_stl(bytes):
        return _parse_binary(bytes)
    var text: String
    try:
        text = String(from_utf8=Span(bytes))
    except reason:
        raise Error("STL: the file starts as text and is not UTF-8")
    return parse_stl_text(text)


def read_stl(path: String) raises -> StlModel:
    """Read an STL file into a model.

    Args:
        path: The file to read.

    Returns:
        Its model; see `parse_stl`.

    Raises:
        Error: If the file cannot be read, or for anything `parse_stl`
            refuses.
    """
    return parse_stl(Path(path).read_bytes())
