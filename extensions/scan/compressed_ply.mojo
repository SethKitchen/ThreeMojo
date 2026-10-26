# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Compressed PLY files, PlayCanvas's packed Gaussian splats, read as
`readPly` in `@playcanvas/splat-transform` 3.10.1 reads them.

SuperSplat writes this format, often as `.compressed.ply`. It is a binary
little-endian PLY file with two or three elements:

- **`chunk`**: one row for each 256 splats, in file order. Each row holds
  the least and the most of the chunk's centers, `min_x` to `max_z`, and
  of its scale logarithms, `min_scale_x` to `max_scale_z`. A row can also
  hold the least and the most of its colors, `min_r` to `max_b`.
- **`vertex`**: four 32-bit words a splat. `packed_position` and
  `packed_scale` hold 11, 10 and 11 bits for x, y and z, from the top
  bit down, each a fraction of the way from the chunk's least to its
  most. `packed_rotation` holds, in its top two bits, which component of
  w, x, y and z is the largest, and three 10-bit numbers for the others,
  each `(n / 1023 - 0.5) * sqrt(2)`; the largest makes the rotation a
  unit. `packed_color` holds a byte each for red, green, blue and
  opacity, from the top byte down.
- **`sh`**, which is optional: 9, 24 or 45 bytes a splat, `f_rest_0` and
  on, the higher bands in the order of a splat PLY file. A byte `b` is
  `(n - 0.5) * 8`, with `n` 0 for 0, 1 for 255, and `(b + 0.5) / 256`
  for the others.

A color byte is a fraction `c` of 255, or of the chunk's color range when
the chunk has one. The zeroth band is `(c - 0.5) / SH_C0`, and the
opacity's logit is `-ln(1 / a - 1)`.

The reader makes the numbers that splat-transform makes, in the same
order and rounded to `Float32` at the same places. It then builds the
splats as `loaders.gaussian_splat_ply` builds them from a PLY file. So a
compressed PLY file and the PLY file that splat-transform writes from it
give the same splats. The header's comments give the `SplatModel`, as
`extensions.scan.scene` says.

**The header.** The header ends at the first `end_header` line in the
first 128 KiB. Its first line is `ply`. Its words are split at spaces.
Its lines are `format`, `comment`, `element name count` and `property
type name`, with the types `char`, `uchar`, `short`, `ushort`, `int`,
`uint`, `float` and `double`. A `ply` or an `end_header` line inside it
is skipped. The reader keeps byte ranges of the header and no text, so
that it runs in the WebAssembly build of `window.capi_splat`, which has no
strings.

**What is refused.** A header that is not as above, that has a list
property, or that counts more than `COMPRESSED_PLY_MOST_ROWS` rows. A file whose `vertex` element has no `packed_position`, which
is a plain PLY file for `loaders.gaussian_splat_ply`. A format other than
binary little-endian. A file with no `chunk` element, or with a missing
`packed` word, chunk bound or color bound. A `packed` word that is not a
`uint`. A count of chunks that is not one for each 256 splats. A count
of `sh` bytes that is not 0, 9, 24 or 45, an `sh` byte that is not a
`uchar`, and an `sh` element with another count of rows. No splats. A file
shorter than its header says.
"""

from core.gaussian_splat_utils import (
    GaussianSplatGeometry,
    clamped_byte,
    create_gaussian_splat_geometry,
    packed_band,
    sh_band_components,
    sh_band_words,
    sigmoid,
    write_color_bytes_from_sh0,
    write_covariance,
)
from extensions.scan.scene import (
    SPLAT_DEFAULT,
    ScanScene,
    splat_model_of_comment,
)
from loaders.ply import (
    PLY_BINARY_LITTLE_ENDIAN,
    PLY_FLOAT32,
    PLY_FLOAT64,
    PLY_INT16,
    PLY_INT32,
    PLY_INT8,
    PLY_UINT16,
    PLY_UINT32,
    PLY_UINT8,
    PlyScalar,
    decode_ply_scalar,
)
from std.math import exp, log, sqrt
from std.pathlib import Path

comptime COMPRESSED_PLY_CHUNK = 256
"""How many splats a `chunk` row holds."""
comptime COMPRESSED_PLY_HEADER_SCAN = 128 * 1024
"""The most bytes the header is looked for in, as splat-transform's probe."""
comptime COMPRESSED_PLY_MOST_ROWS = 4294967295
"""The most rows an element is read with: a count that a 32-bit index holds."""
comptime _END = "\nend_header\n"
"""The text that ends the header."""
comptime _SH_C0 = Float64(0.28209479177387814)
"""splat-transform's zeroth-band constant, one unit in the last place from
`core.gaussian_splat_utils.SH_C0`."""


@fieldwise_init
struct _Range(ImplicitlyCopyable):
    """Bytes of the header: a line, a word, a name or a comment."""

    var start: Int
    """The first byte."""
    var end: Int
    """One past the last byte."""


@fieldwise_init
struct _Property(Copyable, Movable):
    """One `property` line, and where its value is in a row."""

    var name: _Range
    """The property's name."""
    var scalar: PlyScalar
    """Its type."""
    var offset: Int
    """Its first byte in a row."""


@fieldwise_init
struct _Element(Copyable, Movable):
    """One `element` line, its properties, and where its rows are."""

    var name: _Range
    """The element's name."""
    var rows: Int
    """How many rows it has."""
    var stride: Int
    """How many bytes a row takes."""
    var start: Int
    """The first byte of its first row in the file."""
    var properties: List[_Property]
    """Its properties, in row order."""


struct _Header(Movable):
    """A PLY header, read as splat-transform's `readHeader` reads it.

    The header keeps byte ranges of the file and no text, so that the
    reader runs where a module has no strings, as the WebAssembly build of
    `window.capi_splat` has none.
    """

    var comments: List[_Range]
    """The comments, without their leading `comment `."""
    var format: _Range
    """The format's name, or no bytes when there is no `format` line."""
    var elements: List[_Element]
    """The elements, in file order."""
    var size: Int
    """The bytes the header takes, its last line feed included."""

    def __init__(
        out self,
        var comments: List[_Range],
        format: _Range,
        var elements: List[_Element],
        size: Int,
    ):
        """Hold a header.

        Args:
            comments: The comments.
            format: The format's name.
            elements: The elements.
            size: The header's bytes.
        """
        self.comments = comments^
        self.format = format
        self.elements = elements^
        self.size = size


def _is(bytes: List[UInt8], part: _Range, word: StaticString) -> Bool:
    """Return whether bytes of the file are a word.

    Args:
        bytes: The file.
        part: The bytes.
        word: The word.

    Returns:
        Whether they are the same bytes.
    """
    var letters = word.as_bytes()
    if part.end - part.start != len(letters):
        return False
    # Every word has a byte or more: the loop always runs.
    for k in range(len(letters)):  # pragma: no branch
        if bytes[part.start + k] != letters[k]:
            return False
    return True


def _text(bytes: List[UInt8], part: _Range) -> String:
    """Return bytes of the file as text, for an error.

    Args:
        bytes: The file.
        part: The bytes.

    Returns:
        The text, with any byte that is not UTF-8 replaced.
    """
    return String(from_utf8_lossy=Span(bytes)[part.start : part.end])


def _property(bytes: List[UInt8], element: _Element, word: StaticString) -> Int:
    """Return which property of an element has a name.

    Args:
        bytes: The file.
        element: The element.
        word: The name.

    Returns:
        Its place in the row, or -1.
    """
    for index in range(len(element.properties)):
        if _is(bytes, element.properties[index].name, word):
            return index
    return -1


def _element(bytes: List[UInt8], header: _Header, word: StaticString) -> Int:
    """Return which element has a name.

    Args:
        bytes: The file.
        header: The header.
        word: The name.

    Returns:
        Its place in the file, or -1.
    """
    for index in range(len(header.elements)):
        if _is(bytes, header.elements[index].name, word):
            return index
    return -1


def _scalar(bytes: List[UInt8], part: _Range) raises -> PlyScalar:
    """Return the type that a `property` line names.

    Args:
        bytes: The file.
        part: The type's name: `char`, `uchar`, `short`, `ushort`, `int`,
            `uint`, `float` or `double`.

    Returns:
        The type.

    Raises:
        Error: If the name is none of these.
    """
    var names: List[StaticString] = [
        "char",
        "uchar",
        "short",
        "ushort",
        "int",
        "uint",
        "float",
        "double",
    ]
    var scalars: List[PlyScalar] = [
        PLY_INT8,
        PLY_UINT8,
        PLY_INT16,
        PLY_UINT16,
        PLY_INT32,
        PLY_UINT32,
        PLY_FLOAT32,
        PLY_FLOAT64,
    ]
    # The names are eight: the loop always runs.
    for index in range(len(names)):  # pragma: no branch
        if _is(bytes, part, names[index]):
            return scalars[index]
    raise Error(
        "Compressed PLY: an invalid property line, type '"
        + _text(bytes, part)
        + "'"
    )


def _words(bytes: List[UInt8], line: _Range) -> List[_Range]:
    """Return a line's words, split at spaces.

    Args:
        bytes: The file.
        line: The line.

    Returns:
        The words that are not empty.
    """
    var words = List[_Range]()
    var start = line.start
    # The range holds the line's end at least: the loop always runs.
    for at in range(line.start, line.end + 1):  # pragma: no branch
        if at == line.end or bytes[at] == 32:
            if at > start:
                words.append(_Range(start, at))
            start = at + 1
    return words^


def _count(bytes: List[UInt8], part: _Range) raises -> Int:
    """Return the count of an `element` line.

    Args:
        bytes: The file.
        part: The count: digits, with a sign or none.

    Returns:
        The count.

    Raises:
        Error: If it is not digits, it is negative, or it is above
            `COMPRESSED_PLY_MOST_ROWS`.
    """
    var at = part.start
    var negative = bytes[at] == 45
    if negative or bytes[at] == 43:
        at += 1
    var value = 0
    if at == part.end:
        raise Error("Compressed PLY: not a count: " + _text(bytes, part))
    # A count with no digit is refused above: the loop always runs.
    for k in range(at, part.end):  # pragma: no branch
        var digit = Int(bytes[k]) - 48
        if digit < 0 or digit > 9:
            raise Error("Compressed PLY: not a count: " + _text(bytes, part))
        value = min(value * 10 + digit, COMPRESSED_PLY_MOST_ROWS + 1)
    if negative and value > 0:
        raise Error("Compressed PLY: a negative count: " + _text(bytes, part))
    if value > COMPRESSED_PLY_MOST_ROWS:
        raise Error("Compressed PLY: too large a count: " + _text(bytes, part))
    return value


def _end(bytes: List[UInt8]) -> Int:
    """Return where the header's end text starts, or -1.

    Args:
        bytes: The file.

    Returns:
        The first place of `\\nend_header\\n` in the scanned bytes, or -1.
    """
    var marker = _END.as_bytes()
    var limit = min(len(bytes), COMPRESSED_PLY_HEADER_SCAN)
    for at in range(limit - len(marker) + 1):
        var found = True
        for k in range(len(marker)):  # pragma: no branch
            if bytes[at + k] != marker[k]:
                found = False
                break
        if found:
            return at
    return -1


def _header(bytes: List[UInt8]) raises -> _Header:
    """Read a PLY header as splat-transform's `readHeader` reads it.

    Args:
        bytes: The file.

    Returns:
        The header, each element's rows placed after the ones before it.

    Raises:
        Error: If the header is not as the module docstring says.
    """
    var marker = _end(bytes)
    if marker < 0:
        raise Error("Compressed PLY: end_header is not in the first 128 KiB")
    var size = marker + _END.byte_length()
    var lines = List[_Range]()
    var begin = 0
    # The header ends in a line feed: the loop always runs.
    for at in range(size):  # pragma: no branch
        if bytes[at] == 10:
            if at > begin:
                lines.append(_Range(begin, at))
            begin = at + 1
    if not _is(bytes, lines[0], "ply"):
        raise Error("Compressed PLY: the header does not start with ply")
    var comments = List[_Range]()
    var format = _Range(0, 0)
    var elements = List[_Element]()
    # The text holds `ply` and, after it, an `end_header` line: the loop
    # always runs.
    for index in range(1, len(lines)):  # pragma: no branch
        var line = lines[index]
        var words = _words(bytes, line)
        var keyword = _Range(line.start, line.start)
        if len(words) > 0:
            keyword = words[0]
        if _is(bytes, keyword, "ply") or _is(bytes, keyword, "end_header"):
            continue
        if _is(bytes, keyword, "format"):
            format = words[1] if len(words) > 1 else _Range(0, 0)
        elif _is(bytes, keyword, "comment"):
            comments.append(_Range(min(line.start + 8, line.end), line.end))
        elif _is(bytes, keyword, "element"):
            if len(words) != 3:
                raise Error("Compressed PLY: an invalid element line")
            var rows = _count(bytes, words[2])
            elements.append(_Element(words[1], rows, 0, 0, List[_Property]()))
        elif _is(bytes, keyword, "property"):
            if len(elements) == 0 or len(words) != 3:
                raise Error("Compressed PLY: an invalid property line")
            var scalar = _scalar(bytes, words[1])
            ref element = elements[len(elements) - 1]
            element.properties.append(
                _Property(words[2], scalar, element.stride)
            )
            element.stride += scalar.size()
        else:
            raise Error(
                "Compressed PLY: an unrecognized header line '"
                + _text(bytes, keyword)
                + "'"
            )
    var start = size
    for index in range(len(elements)):
        elements[index].start = start
        start += elements[index].rows * elements[index].stride
    if start > len(bytes):
        raise Error(
            "Compressed PLY: the file is "
            + String(len(bytes))
            + " bytes, and its header needs "
            + String(start)
        )
    return _Header(comments^, format, elements^, size)


def _is_packed(bytes: List[UInt8], header: _Header) -> Bool:
    """Return whether a header's `vertex` element has `packed_position`.

    Args:
        bytes: The file.
        header: The header.

    Returns:
        Whether it is splat-transform's mark of a compressed file.
    """
    var vertex = _element(bytes, header, "vertex")
    return (
        vertex >= 0
        and _property(bytes, header.elements[vertex], "packed_position") >= 0
    )


def is_compressed_ply(bytes: List[UInt8]) -> Bool:
    """Return whether a file is a compressed PLY file.

    Args:
        bytes: The file.

    Returns:
        Whether its header can be read and its `vertex` element has
        `packed_position`, as splat-transform tells the formats apart.
        The rest of the file is not checked.
    """
    try:
        return _is_packed(bytes, _header(bytes))
    except:
        return False


def _required(
    bytes: List[UInt8], header: _Header, word: StaticString
) raises -> Int:
    """Return which element has a name, or refuse.

    Args:
        bytes: The file.
        header: The header.
        word: `chunk` or `vertex`.

    Returns:
        Its place in the file.

    Raises:
        Error: If there is none.
    """
    var index = _element(bytes, header, word)
    if index < 0:
        raise Error(
            "Compressed PLY: the file has no " + String(word) + " element"
        )
    return index


def _typed(element: _Element, index: Int, scalar: PlyScalar) -> Int:
    """Return where a property of one type is in a row.

    Args:
        element: The element.
        index: The property's place, or -1 when the element has none.
        scalar: The type it must have.

    Returns:
        Its first byte in a row; -1 when there is no property, and -2 when
        it has another type.
    """
    if index < 0:
        return -1
    if element.properties[index].scalar != scalar:
        return -2
    return element.properties[index].offset


def _offset(
    bytes: List[UInt8], element: _Element, word: StaticString
) raises -> Int:
    """Return where a `uint` property is in a row, or refuse.

    Args:
        bytes: The file.
        element: The element.
        word: The property's name.

    Returns:
        Its first byte in a row.

    Raises:
        Error: If the element has no such property, or it is not a `uint`.
    """
    var at = _typed(element, _property(bytes, element, word), PLY_UINT32)
    if at == -1:
        raise Error(
            "Compressed PLY: the "
            + _text(bytes, element.name)
            + " element has no "
            + String(word)
        )
    if at == -2:
        raise Error("Compressed PLY: " + String(word) + " must be a uint")
    return at


def _is_rest(bytes: List[UInt8], part: _Range, rest: Int) -> Bool:
    """Return whether a name is `f_rest_` and a number.

    Args:
        bytes: The file.
        part: The name.
        rest: The number, 0 or more.

    Returns:
        Whether the name is `f_rest_` and the number's digits.
    """
    var digits = List[UInt8]()
    var value = rest
    while True:
        digits.append(UInt8(48 + value % 10))
        value //= 10
        if value == 0:
            break
    var prefix = _Range(part.start, min(part.start + 7, part.end))
    if not _is(bytes, prefix, "f_rest_"):
        return False
    if part.end - prefix.end != len(digits):
        return False
    # A number has a digit at least: the loop always runs.
    for k in range(len(digits)):  # pragma: no branch
        if bytes[prefix.end + k] != digits[len(digits) - 1 - k]:
            return False
    return True


def _rest_offset(bytes: List[UInt8], sh: _Element, rest: Int) raises -> Int:
    """Return where an `f_rest` byte is in an `sh` row, or refuse.

    Args:
        bytes: The file.
        sh: The `sh` element.
        rest: Which `f_rest` byte.

    Returns:
        Its first byte in a row.

    Raises:
        Error: If the element has no such byte, or it is not a `uchar`.
    """
    var index = -1
    for at in range(len(sh.properties)):  # pragma: no branch
        if _is_rest(bytes, sh.properties[at].name, rest):
            index = at
            break
    var at = _typed(sh, index, PLY_UINT8)
    if at == -1:
        raise Error(
            "Compressed PLY: the sh element has no f_rest_" + String(rest)
        )
    if at == -2:
        raise Error(
            "Compressed PLY: f_rest_" + String(rest) + " must be a uchar"
        )
    return at


def _bounds(
    bytes: List[UInt8], element: _Element, names: List[StaticString]
) raises -> List[Float64]:
    """Return named properties of every chunk row, as numbers.

    Args:
        bytes: The file.
        element: The `chunk` element.
        names: The properties.

    Returns:
        `rows * len(names)` numbers, each row's together.

    Raises:
        Error: If a property is missing.
    """
    var places = List[Int]()
    var scalars = List[PlyScalar]()
    # Each caller names six or twelve bounds, and a file with splats has a
    # chunk row: the loops always run.
    for name in names:  # pragma: no branch
        var index = _property(bytes, element, name)
        if index < 0:
            raise Error(
                "Compressed PLY: the chunk element has no " + String(name)
            )
        places.append(element.properties[index].offset)
        scalars.append(element.properties[index].scalar)
    var values = List[Float64](capacity=element.rows * len(names))
    for row in range(element.rows):  # pragma: no branch
        var at = element.start + row * element.stride
        for k in range(len(names)):  # pragma: no branch
            values.append(
                decode_ply_scalar(
                    bytes, at + places[k], scalars[k], PLY_BINARY_LITTLE_ENDIAN
                )
            )
    return values^


@always_inline
def _word(bytes: List[UInt8], at: Int) -> UInt32:
    """Return a little-endian 32-bit word.

    Args:
        bytes: The file.
        at: The word's first byte.

    Returns:
        The word.
    """
    return (
        UInt32(bytes[at])
        | (UInt32(bytes[at + 1]) << 8)
        | (UInt32(bytes[at + 2]) << 16)
        | (UInt32(bytes[at + 3]) << 24)
    )


@always_inline
def _unorm(value: UInt32, shift: Int, bits: Int) -> Float64:
    """Return a field of a word as a fraction, splat-transform's
    `unpackUnorm`.

    Args:
        value: The word.
        shift: Where the field's lowest bit is.
        bits: How many bits it has.

    Returns:
        The field divided by its largest value.
    """
    var top = (UInt32(1) << UInt32(bits)) - 1
    return Float64((value >> UInt32(shift)) & top) / Float64(top)


@always_inline
def _lerp(a: Float64, b: Float64, t: Float64) -> Float64:
    """Return splat-transform's `lerp`, `a * (1 - t) + b * t`.

    Args:
        a: The value at 0.
        b: The value at 1.
        t: The fraction.

    Returns:
        The value between them.
    """
    return a * (1 - t) + b * t


def _rest_bytes() -> List[UInt8]:
    """Return the band byte that each `sh` byte gives.

    Returns:
        256 bytes: `(n - 0.5) * 8`, rounded to `Float32`, then made a band
        byte as `loaders.gaussian_splat_ply` makes one.
    """
    var table = List[UInt8](capacity=256)
    for byte in range(256):
        var n = (Float64(byte) + 0.5) / 256
        if byte == 0:
            n = 0
        elif byte == 255:
            n = 1
        var value = Float32((n - 0.5) * 8)
        table.append(clamped_byte(Float64(value) * 128 + 128))
    return table^


def _band(
    bytes: List[UInt8],
    sh: _Element,
    places: List[Int],
    table: List[UInt8],
    count: Int,
    degree: Int,
) raises -> List[UInt8]:
    """Return one band's bytes from the `sh` element.

    Args:
        bytes: The file.
        sh: The `sh` element.
        places: Where each `f_rest` byte is in a row.
        table: The band byte of each `sh` byte.
        count: How many splats.
        degree: The band, 1 through 3.

    Returns:
        The band's bytes.

    Raises:
        Error: Never, for a degree of 1 through 3.
    """
    var band = packed_band(count, degree)
    var stride = len(places) // 3
    # The coefficients of the bands below come first in each channel.
    var offset = degree * degree - 1
    var words = sh_band_words(degree) * 4
    var components = sh_band_components(degree)
    for index in range(count):  # pragma: no branch
        var row = sh.start + index * sh.stride
        for component in range(components):  # pragma: no branch
            var rest = offset + component // 3 + (component % 3) * stride
            band[index * words + component] = table[
                Int(bytes[row + places[rest]])
            ]
    return band^


def parse_compressed_ply(bytes: List[UInt8]) raises -> ScanScene:
    """Read a compressed PLY file's bytes.

    Args:
        bytes: The whole file.

    Returns:
        The splats in file order, and the model the comments name; see the
        module docstring.

    Raises:
        Error: Everything that the module docstring lists.
    """
    var header = _header(bytes)
    if not _is_packed(bytes, header):
        raise Error(
            "Compressed PLY: the vertex element has no packed_position;"
            " read a plain PLY file with loaders.gaussian_splat_ply"
        )
    if not _is(bytes, header.format, "binary_little_endian"):
        raise Error(
            "Compressed PLY: the format must be binary_little_endian, not '"
            + _text(bytes, header.format)
            + "'"
        )
    ref chunk = header.elements[_required(bytes, header, "chunk")]
    ref vertex = header.elements[_required(bytes, header, "vertex")]
    var count = vertex.rows
    if count < 1:
        raise Error("Compressed PLY: a file has at least one splat")
    var chunks = (count + COMPRESSED_PLY_CHUNK - 1) // COMPRESSED_PLY_CHUNK
    if chunk.rows != chunks:
        raise Error(
            "Compressed PLY: "
            + String(count)
            + " splats need "
            + String(chunks)
            + " chunks, and the file has "
            + String(chunk.rows)
        )
    var position = _offset(bytes, vertex, "packed_position")
    var rotation = _offset(bytes, vertex, "packed_rotation")
    var scale = _offset(bytes, vertex, "packed_scale")
    var color = _offset(bytes, vertex, "packed_color")
    var bounds = _bounds(
        bytes,
        chunk,
        [
            "min_x",
            "min_y",
            "min_z",
            "max_x",
            "max_y",
            "max_z",
            "min_scale_x",
            "min_scale_y",
            "min_scale_z",
            "max_scale_x",
            "max_scale_y",
            "max_scale_z",
        ],
    )
    var tinted = _property(bytes, chunk, "min_r") >= 0
    var tints = List[Float64]()
    if tinted:
        tints = _bounds(
            bytes,
            chunk,
            ["min_r", "min_g", "min_b", "max_r", "max_g", "max_b"],
        )

    var degree = 0
    var places = List[Int]()
    var sh_index = _element(bytes, header, "sh")
    if sh_index >= 0:
        ref sh = header.elements[sh_index]
        var rest = len(sh.properties)
        var degrees: List[Int] = [0, 9, 24, 45]
        degree = -1
        for band in range(4):
            if degrees[band] == rest:
                degree = band
        if degree < 0:
            raise Error(
                "Compressed PLY: "
                + String(rest)
                + " sh bytes a splat, not 0, 9, 24 or 45"
            )
        if sh.rows != count:
            raise Error(
                "Compressed PLY: the sh element has "
                + String(sh.rows)
                + " rows for "
                + String(count)
                + " splats"
            )
        for r in range(rest):
            places.append(_rest_offset(bytes, sh, r))

    var norm = 1 / (sqrt(Float64(2)) * 0.5)
    var centers = List[Float32](capacity=count * 3)
    var covariances = List[Float32](length=count * 6, fill=0)
    var colors = List[UInt8](length=count * 4, fill=0)
    for index in range(count):  # pragma: no branch
        var row = vertex.start + index * vertex.stride
        var box = (index // COMPRESSED_PLY_CHUNK) * 12
        var p = _word(bytes, row + position)
        centers.append(
            Float32(_lerp(bounds[box], bounds[box + 3], _unorm(p, 21, 11)))
        )
        centers.append(
            Float32(_lerp(bounds[box + 1], bounds[box + 4], _unorm(p, 11, 10)))
        )
        centers.append(
            Float32(_lerp(bounds[box + 2], bounds[box + 5], _unorm(p, 0, 11)))
        )

        var r = _word(bytes, row + rotation)
        var a = (_unorm(r, 20, 10) - 0.5) * norm
        var b = (_unorm(r, 10, 10) - 0.5) * norm
        var c = (_unorm(r, 0, 10) - 0.5) * norm
        var m = sqrt(max(Float64(0), 1 - (a * a + b * b + c * c)))
        var largest = Int(r >> 30)
        var q0 = Float32(a)
        var q1 = Float32(b if largest > 1 else a)
        var q2 = Float32(c if largest > 2 else b)
        var q3 = Float32(c)
        if largest == 0:
            q0 = Float32(m)
        elif largest == 1:
            q1 = Float32(m)
        elif largest == 2:
            q2 = Float32(m)
        else:
            q3 = Float32(m)

        var s = _word(bytes, row + scale)
        var sx = Float32(
            _lerp(bounds[box + 6], bounds[box + 9], _unorm(s, 21, 11))
        )
        var sy = Float32(
            _lerp(bounds[box + 7], bounds[box + 10], _unorm(s, 11, 10))
        )
        var sz = Float32(
            _lerp(bounds[box + 8], bounds[box + 11], _unorm(s, 0, 11))
        )
        # The PLY order is w, x, y and z.
        write_covariance(
            covariances,
            index * 6,
            exp(Float64(sx)),
            exp(Float64(sy)),
            exp(Float64(sz)),
            Float64(q1),
            Float64(q2),
            Float64(q3),
            Float64(q0),
        )

        var k = _word(bytes, row + color)
        var red = _unorm(k, 24, 8)
        var green = _unorm(k, 16, 8)
        var blue = _unorm(k, 8, 8)
        if tinted:
            var tint = (index // COMPRESSED_PLY_CHUNK) * 6
            red = _lerp(tints[tint], tints[tint + 3], red)
            green = _lerp(tints[tint + 1], tints[tint + 4], green)
            blue = _lerp(tints[tint + 2], tints[tint + 5], blue)
        var opacity = Float32(-log(1 / _unorm(k, 0, 8) - 1))
        write_color_bytes_from_sh0(
            colors,
            index * 4,
            Float64(Float32((red - 0.5) / _SH_C0)),
            Float64(Float32((green - 0.5) / _SH_C0)),
            Float64(Float32((blue - 0.5) / _SH_C0)),
            sigmoid(Float64(opacity)),
        )

    var table = _rest_bytes()
    var bands = List[List[UInt8]]()
    for band in range(1, 4):
        if band <= degree:
            bands.append(
                _band(
                    bytes,
                    header.elements[sh_index],
                    places,
                    table,
                    count,
                    band,
                )
            )
        else:
            bands.append(List[UInt8]())
    var geometry = create_gaussian_splat_geometry(
        centers^,
        covariances^,
        colors^,
        bands[0].copy(),
        bands[1].copy(),
        bands[2].copy(),
    )
    var model = SPLAT_DEFAULT
    for comment in header.comments:
        model = splat_model_of_comment(
            model, Span(bytes)[comment.start : comment.end]
        )
    return ScanScene(geometry^, model)


def read_compressed_ply(path: String) raises -> ScanScene:
    """Read a compressed PLY file.

    Args:
        path: The file.

    Returns:
        Its splats; see `parse_compressed_ply`.

    Raises:
        Error: If the file cannot be read, or anything that
            `parse_compressed_ply` raises.
    """
    return parse_compressed_ply(Path(path).read_bytes())
