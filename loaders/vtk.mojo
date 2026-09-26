# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""VTK poly data, from three.js `examples/jsm/loaders/VTKLoader.js`.

`parse_vtk` reads the three kinds of file three.js reads, and picks one
as three.js does, from the first 250 bytes: an XML file when its first
line holds `xml`, a legacy text file when its third line holds `ASCII`,
and a legacy binary file otherwise. Each gives one `BufferGeometry`.

**Legacy text.** `parse_vtk_ascii` reads `POINTS`, `POLYGONS`,
`TRIANGLE_STRIPS`, and in `POINT_DATA` or `CELL_DATA` the `NORMALS` and
`COLOR_SCALARS` sections, with three.js's patterns:

- A line of points gives each run of three numbers on it. A line that
  starts with a word gives its first run only.
- A polygon is cut into a fan and a strip into triangles, and each new
  section adds to the index.
- A normal is kept for each point when there is one for each point.
- A color is decoded from sRGB. When there is one color for each index
  entry, three.js takes them as cell colors: the geometry loses its index
  and each triangle's color is decoded a second time, as three.js does.
  When there is one for each point, the colors are the points' colors.

**Legacy binary.** `parse_vtk_binary` reads big-endian `POINTS`,
`POLYGONS` and `TRIANGLE_STRIPS` sections, and takes the line after
`POINT_DATA` to start the normals, as three.js does. A new `POLYGONS` or
`TRIANGLE_STRIPS` section replaces the index.

**XML.** `parse_vtk_xml` reads a `PolyData` file's first `Piece`: its
`Points`, the normals that `PointData` names, `Strips` and then `Polys`,
where `Polys` replaces the strips' index, as three.js does. A data array
can be text, base64 with a byte count before it, base64 zlib blocks when
the file names a `compressor`, or appended base64. An `Int64` array keeps
the low half of each value. The strips are cut as three.js cuts them:
each strip reads the connectivity from its start.

**Where three.js's quirks are kept.** A file shorter than 250 bytes, or
whose third line is past them, is refused, as three.js throws on it. The
patterns read the text as JavaScript's code units do, and share one
`lastIndex`, as three.js's global pattern does. An index entry that is
not a number is point zero. An index that the file leaves empty is kept
empty, so the geometry's draw range is empty, as three.js's empty index
draws nothing.

**What is refused.** A `DATASET` that is not `POLYDATA`, as three.js
throws on it. Everything three.js throws on as it reads: a value past
the end of the file, base64 whose length is not a multiple of four, a
data array longer than what it is copied to, and a part of the XML that
three.js reads but the file does not have. A binary line with no end and
a count that is not a number, which three.js never finishes reading. A
text or XML file that is not UTF-8, which three.js decodes with
replacement characters. And an index past the points, which three.js
keeps and draws from undefined positions.
"""

from core.buffer_attribute import BufferAttribute
from core.buffer_geometry import COLOR, NORMAL, POSITION, BufferGeometry
from loaders.js_text import (
    is_js_space,
    js_part,
    js_string,
    js_trim,
    js_units,
)
from loaders.js_number import (
    js_parse_float,
    js_parse_int,
    js_pow,
    js_string_to_number,
)
from loaders.xml import NO_ELEMENT, XmlDocument, parse_xml
from render.inflate import inflate
from std.math import floor, isinf, isnan, nan, trunc
from std.memory import bitcast
from std.pathlib import Path

# How many bytes three.js reads to choose the kind of file.
comptime VTK_META_BYTES = 250
# The longest typed array this port makes. three.js makes any length the
# browser allows.
comptime MAX_VTK_ARRAY = 1 << 28
# What `_only` returns when an element has more than one child of a name,
# which three.js's `xmlToJson` makes an array.
comptime _MANY = -2


def _is_digit(unit: Int) -> Bool:
    """Return True for `0` to `9`.

    Args:
        unit: The code unit.

    Returns:
        Whether it is a digit.
    """
    return unit >= 48 and unit <= 57


def _starts(units: List[Int], prefix: String) -> Bool:
    """Return True if code units start with an ASCII prefix.

    Args:
        units: The code units.
        prefix: The prefix.

    Returns:
        Whether they start with it.
    """
    var bytes = prefix.as_bytes()
    if len(units) < len(bytes):
        return False
    for k in range(len(bytes)):  # pragma: no branch
        if units[k] != Int(bytes[k]):
            return False
    return True


def _word(units: List[Int], which: Int) -> Optional[String]:
    """Return JavaScript's `line.split( ' ' )[ which ]`.

    Args:
        units: The line.
        which: Which word, from zero.

    Returns:
        The text between the spaces around it, or none past the last.
    """
    var start = 0
    var seen = 0
    for k in range(len(units)):  # pragma: no branch
        if units[k] == 32:
            if seen == which:
                return js_string(units, start, k)
            seen += 1
            start = k + 1
    if seen == which:
        return js_string(units, start, len(units))
    return None


def _second_word(units: List[Int]) -> String:
    """Return JavaScript's `line.split( ' ' )[ 1 ]` as a string.

    Args:
        units: The line.

    Returns:
        The second word, or `undefined` when there is no space.
    """
    return _word(units, 1).or_else("undefined")


def _decoded(bytes: Span[UInt8, _]) raises -> String:
    """Return a file as text, as `TextDecoder` decodes it: a leading byte
    order mark dropped.

    Args:
        bytes: The file.

    Returns:
        The text.

    Raises:
        Error: If the bytes are not UTF-8.
    """
    var start = 0
    var marked = (
        len(bytes) >= 3
        and bytes[0] == 0xEF
        and bytes[1] == 0xBB
        and bytes[2] == 0xBF
    )
    if marked:
        start = 3
    try:
        return String(from_utf8=bytes[start:])
    except:
        raise Error("VTK: the file is not UTF-8 text")


def _srgb_to_linear(c: Float64) -> Float64:
    """Return three.js's `SRGBToLinear`.

    Args:
        c: A channel in sRGB.

    Returns:
        The channel in linear light.
    """
    if c < 0.04045:
        return c * 0.0773993808
    return js_pow(c * 0.9478672986 + 0.0521327014, 2.4)


def _to_uint32(value: Float64) -> Float64:
    """Return JavaScript's `ToUint32`, as a typed array stores a value.

    Args:
        value: The value.

    Returns:
        The value as a 32-bit unsigned integer; zero for NaN.
    """
    if isnan(value) or isinf(value):
        return 0
    var t = trunc(value)
    return t - floor(t / 4294967296.0) * 4294967296.0


def _to_int32(value: Float64) -> Float64:
    """Return JavaScript's `ToInt32`.

    Args:
        value: The value.

    Returns:
        The value as a 32-bit signed integer; zero for NaN.
    """
    var u = _to_uint32(value)
    return u - 4294967296.0 if u >= 2147483648.0 else u


def _to_index(value: Float64, what: String) raises -> Int:
    """Return JavaScript's `ToIndex`, the length a typed array is made
    with.

    Args:
        value: The length asked for.
        what: What the array holds, for the message.

    Returns:
        The length: zero for NaN, and whole.

    Raises:
        Error: If the length is negative, as three.js throws a
            `RangeError`, or longer than `MAX_VTK_ARRAY`.
    """
    if isnan(value):
        return 0
    var length = trunc(value)
    if length < 0:
        raise Error("VTK: " + what + " cannot have a negative length")
    if length > Float64(MAX_VTK_ARRAY):
        raise Error("VTK: " + what + " is longer than this port makes")
    return Int(length)


def _geometry(
    positions: List[Float64],
    normals: List[Float64],
    indices: List[Float64],
) raises -> BufferGeometry:
    """Return three.js's indexed geometry: the index, the positions, and
    the normals when there is one for each point.

    Args:
        positions: Three numbers a point.
        normals: Three numbers a point, or any other count to leave out.
        indices: The index entries as a typed array stores them.

    Returns:
        The geometry. An empty index gives an empty draw range.

    Raises:
        Error: If the positions are not three numbers a point, or an
            index entry is past the points.
    """
    if len(positions) % 3 != 0:
        raise Error("VTK: the points are not three numbers each")
    var count = len(positions) // 3
    var index = List[Int](capacity=len(indices))
    for value in indices:
        if value >= Float64(count):
            raise Error(
                "VTK: an index names point "
                + String(Int(value))
                + " of "
                + String(count)
            )
        index.append(Int(value))
    var geometry = BufferGeometry()
    geometry.set_index(index^)
    if len(indices) == 0:
        geometry.set_draw_range(0, 0)
    geometry.set_attribute(String(POSITION), _attribute(positions))
    if len(normals) == len(positions):
        geometry.set_attribute(String(NORMAL), _attribute(normals))
    return geometry^


def _typed_geometry(
    positions: List[Float64],
    normals: List[Float64],
    indices: List[Float64],
    has_points: Bool,
    has_normals: Bool,
    has_index: Bool,
) raises -> BufferGeometry:
    """Return the geometry of a binary or XML file, which three.js builds
    with `new BufferAttribute( array )`: that throws on an array that was
    never made a typed array.

    Args:
        positions: Three numbers a point.
        normals: Three numbers a point, or any other count to leave out.
        indices: The index entries as a typed array stores them.
        has_points: Whether the file made the points a typed array.
        has_normals: Whether it made the normals one.
        has_index: Whether it made the index one.

    Returns:
        What `_geometry` gives.

    Raises:
        Error: If the index or the points were never made, or the normals
            were not and would be kept, as three.js throws; and anything
            `_geometry` refuses.
    """
    if not has_index:
        raise Error("VTK: the file has no cells to index")
    if not has_points:
        raise Error("VTK: the file has no points")
    if not has_normals and len(normals) == len(positions):
        raise Error("VTK: the file has no normals, and no points")
    return _geometry(positions, normals, indices)


def _attribute(values: List[Float64]) raises -> BufferAttribute:
    """Return three numbers a vertex as a `Float32Array` holds them.

    Args:
        values: The numbers.

    Returns:
        The attribute.

    Raises:
        Error: If the numbers are not three a vertex.
    """
    var floats = List[Float32](capacity=len(values))
    for value in values:
        floats.append(Float32(value))
    return BufferAttribute(floats^, 3)


def _stored_indices(values: List[Float64]) -> List[Float64]:
    """Return an index as three.js's `setIndex( array )` stores it: in a
    `Uint32Array` when an entry reaches 65535, a `Uint16Array` otherwise.

    Args:
        values: The entries three.js pushed.

    Returns:
        The entries as stored. NaN is zero.
    """
    var wide = False
    for value in values:
        if value >= 65535:
            wide = True
    var out = List[Float64](capacity=len(values))
    for value in values:
        var stored = _to_uint32(value)
        if not wide:
            stored = stored - floor(stored / 65536.0) * 65536.0
        out.append(stored)
    return out^


# --- legacy text -------------------------------------------------------------


def _number_end(line: List[Int], at: Int) -> Int:
    """Return where one number of three.js's `pat3Floats` ends, as
    `-?\\d+\\.?[\\d\\-\\+e]*` matches it greedily.

    Args:
        line: The line.
        at: Where the number starts.

    Returns:
        One past its end, or -1 when no number starts there.
    """
    var n = len(line)
    var i = at
    # `at` is inside the line: a start before its end, or the character
    # after a run of spaces, which a trimmed line never ends with.
    if line[i] == 45:
        i += 1
    var first = i
    while i < n and _is_digit(line[i]):
        i += 1
    if i == first:
        return -1
    if i < n and line[i] == 46:
        i += 1
    while i < n and (
        _is_digit(line[i]) or line[i] == 45 or line[i] == 43 or line[i] == 101
    ):
        i += 1
    return i


def _three_floats(line: List[Int], mut last_index: Int) -> List[Float64]:
    """Return three.js's `pat3Floats.exec( line )`: the next three numbers
    apart by white space, from `lastIndex`.

    Args:
        line: The line.
        last_index: The pattern's `lastIndex`, which the match moves past
            it, or sets to zero when there is none.

    Returns:
        The three numbers read with `parseFloat`, or none.
    """
    var n = len(line)
    if last_index > n:
        last_index = 0
        return []
    for start in range(last_index, n):
        var at = start
        var ends = List[Int]()
        for group in range(3):  # pragma: no branch
            if group > 0:
                if at >= n or not is_js_space(line[at]):
                    break
                # The line is trimmed: a character follows the spaces.
                while is_js_space(line[at]):
                    at += 1
            var end = _number_end(line, at)
            if end < 0:
                break
            ends.append(at)
            ends.append(end)
            at = end
        if len(ends) == 6:
            last_index = at
            return [
                js_parse_float(js_string(line, ends[0], ends[1])),
                js_parse_float(js_string(line, ends[2], ends[3])),
                js_parse_float(js_string(line, ends[4], ends[5])),
            ]
    last_index = 0
    return []


def _starts_with_word(line: List[Int]) -> Bool:
    """Return three.js's `patWord.exec( line ) !== null`: the line starts
    with what is not a digit, a point, white space or a minus.

    Args:
        line: The line.

    Returns:
        Whether it does.
    """
    # Called when the line gave three numbers, so it is not empty; it is
    # trimmed, so it never starts with white space.
    var u = line[0]
    return not (_is_digit(u) or u == 46 or u == 45)


def _head(line: List[Int], prefix: String, runs: List[Int]) -> Bool:
    """Return True if a line starts with a prefix and runs of characters,
    as three.js's section patterns match.

    Args:
        line: The line.
        prefix: The word it starts with.
        runs: What follows, one run each: 0 for spaces, 1 for digits, 2
            for word characters, and 3 for the character `3`.

    Returns:
        Whether the line matches.
    """
    if not _starts(line, prefix):
        return False
    var at = prefix.byte_length()
    for kind in runs:  # pragma: no branch
        if kind == 3:
            return at < len(line) and line[at] == 51
        var end = at
        while end < len(line):
            var u = line[end]
            var word = (
                _is_digit(u)
                or (u >= 65 and u <= 90)
                or (u >= 97 and u <= 122)
                or u == 95
            )
            var fits = (
                (kind == 0 and u == 32)
                or (kind == 1 and _is_digit(u))
                or (kind == 2 and word)
            )
            if not fits:
                break
            end += 1
        if end == at:
            return False
        at = end
    return True


def _connectivity(line: List[Int]) -> List[Float64]:
    """Return three.js's `patConnectivity`, `^(\\d+)\\s+([\\s\\d]*)`: the
    count, then each of the words after it, split at white space.

    Args:
        line: The line.

    Returns:
        The count and each word, read with `parseInt`, NaN for an empty
        word. None when the line does not match.
    """
    var n = len(line)
    var at = 0
    while at < n and _is_digit(line[at]):
        at += 1
    if at == 0 or at >= n or not is_js_space(line[at]):
        return []
    var out: List[Float64] = [js_parse_int(js_string(line, 0, at))]
    # The line is trimmed: a character follows the spaces.
    while is_js_space(line[at]):
        at += 1
    var start = at
    var end = at
    while end < n and (_is_digit(line[end]) or is_js_space(line[end])):
        end += 1
    # JavaScript's `split( /\s+/ )`: an empty text is one empty word.
    var word = start
    var k = start
    while k < end:
        if is_js_space(line[k]):
            out.append(js_parse_int(js_string(line, word, k)))
            while k < end and is_js_space(line[k]):
                k += 1
            word = k
        else:
            k += 1
    out.append(js_parse_int(js_string(line, word, end)))
    return out^


def _entry(words: List[Float64], at: Int) -> Float64:
    """Return `parseInt( inds[ at ] )`, NaN past the words.

    Args:
        words: The count, then the words.
        at: Which word, from zero after the count.

    Returns:
        The word's value.
    """
    if at + 1 < len(words):
        return words[at + 1]
    return nan[DType.float64]()


def _cell(words: List[Float64], line: Int) raises -> Int:
    """Return a cell's count of points, as a loop bound.

    Args:
        words: The count, then the words.
        line: The line's number, for the message.

    Returns:
        The count, or zero for fewer than three.

    Raises:
        Error: If the count is more than the words could name, which
            three.js fills out with point zero for as long as it takes.
    """
    var count = words[0]
    if count < 3:
        return 0
    if count > Float64(len(words) + 2):
        raise Error(
            "VTK: line " + String(line) + " names more points than it gives"
        )
    return Int(count)


def parse_vtk_ascii(text: String) raises -> BufferGeometry:
    """Read a legacy VTK text file, three.js's `parseASCII`.

    Args:
        text: The file.

    Returns:
        The geometry.

    Raises:
        Error: If the `DATASET` is not `POLYDATA`, a cell names more
            points than its line gives, or an index is past the points.
    """
    var units = js_units(text)
    var indices = List[Float64]()
    var positions = List[Float64]()
    var colors = List[Float64]()
    var normals = List[Float64]()
    var in_points = False
    var in_polygons = False
    var in_strips = False
    var in_point_data = False
    var in_cell_data = False
    var in_colors = False
    var in_normals = False
    # The one `lastIndex` of three.js's global `pat3Floats`.
    var last_index = 0
    var start = 0
    var number = 0
    while start <= len(units):
        var end = start
        while end < len(units) and units[end] != 10:
            end += 1
        var line = js_trim(js_part(units, start, end))
        start = end + 1
        number += 1
        if _starts(line, "DATASET"):
            var dataset = _second_word(line)
            if dataset != "POLYDATA":
                raise Error("Unsupported DATASET type: " + dataset)
        elif in_points:
            while True:
                var three = _three_floats(line, last_index)
                if len(three) == 0 or _starts_with_word(line):
                    break
                positions.extend(three^)
        elif in_polygons:
            var words = _connectivity(line)
            if len(words) > 0:
                var count = _cell(words, number)
                if count > 0:
                    var i0 = _entry(words, 0)
                    for j in range(count - 2):  # pragma: no branch
                        indices.append(i0)
                        indices.append(_entry(words, j + 1))
                        indices.append(_entry(words, j + 2))
        elif in_strips:
            var words = _connectivity(line)
            if len(words) > 0:
                var count = _cell(words, number)
                for j in range(max(count - 2, 0)):
                    indices.append(_entry(words, j))
                    if j % 2 == 1:
                        indices.append(_entry(words, j + 2))
                        indices.append(_entry(words, j + 1))
                    else:
                        indices.append(_entry(words, j + 1))
                        indices.append(_entry(words, j + 2))
        elif in_point_data or in_cell_data:
            if in_colors:
                while True:
                    var three = _three_floats(line, last_index)
                    if len(three) == 0 or _starts_with_word(line):
                        break
                    for c in three:  # pragma: no branch
                        colors.append(_srgb_to_linear(c))
            elif in_normals:
                while True:
                    var three = _three_floats(line, last_index)
                    if len(three) == 0 or _starts_with_word(line):
                        break
                    normals.extend(three^)
        if _starts(line, "POLYGONS "):
            in_polygons = True
            in_points = False
            in_strips = False
        elif _starts(line, "POINTS "):
            in_polygons = False
            in_points = True
            in_strips = False
        elif _starts(line, "TRIANGLE_STRIPS "):
            in_polygons = False
            in_points = False
            in_strips = True
        elif _head(line, "POINT_DATA", [0, 1]):
            in_point_data = True
            in_points = False
            in_polygons = False
            in_strips = False
        elif _head(line, "CELL_DATA", [0, 1]):
            in_cell_data = True
            in_points = False
            in_polygons = False
            in_strips = False
        elif _head(line, "COLOR_SCALARS", [0, 2, 0, 3]):
            in_colors = True
            in_normals = False
            in_points = False
            in_polygons = False
            in_strips = False
        elif _head(line, "NORMALS", [0, 2, 0, 2]):
            in_normals = True
            in_colors = False
            in_points = False
            in_polygons = False
            in_strips = False
    var stored = _stored_indices(indices)
    if len(colors) != len(indices):
        var geometry = _geometry(positions, normals, stored)
        if len(colors) == len(positions):
            geometry.set_attribute(String(COLOR), _attribute(colors))
        return geometry^
    # One color for each index entry: three.js's cell colors. The
    # geometry loses its index, and each triangle takes its color decoded
    # once more.
    var indexed = _geometry(positions, normals, stored)
    var flat = List[Float64]()
    var flat_normals = List[Float64]()
    var flat_colors = List[Float64]()
    var normal_each = len(normals) == len(positions)
    for k in range(len(stored)):
        var at = Int(stored[k]) * 3
        for c in range(3):  # pragma: no branch
            flat.append(positions[at + c])
            if normal_each:
                flat_normals.append(normals[at + c])
            flat_colors.append(_srgb_to_linear(colors[(k // 3) * 3 + c]))
    _ = indexed^
    var geometry = BufferGeometry()
    geometry.set_attribute(String(POSITION), _attribute(flat))
    if normal_each:
        geometry.set_attribute(String(NORMAL), _attribute(flat_normals))
    geometry.set_attribute(String(COLOR), _attribute(flat_colors))
    return geometry^


# --- legacy binary -----------------------------------------------------------


struct _Binary:
    """A legacy binary file, read as three.js's `DataView` reads it."""

    var bytes: List[UInt8]

    def __init__(out self, var bytes: List[UInt8]):
        """Hold the file.

        Args:
            bytes: The file.
        """
        self.bytes = bytes^

    def word(self, at: Int) raises -> UInt32:
        """Return the big-endian 32 bits at a byte.

        Args:
            at: The byte.

        Returns:
            The bits.

        Raises:
            Error: If they run past the end, as `DataView` throws.
        """
        if at + 4 > len(self.bytes):
            raise Error("VTK: a value runs past the end, at byte " + String(at))
        var value: UInt32 = 0
        for k in range(4):  # pragma: no branch
            value = (value << 8) | UInt32(self.bytes[at + k])
        return value

    def float(self, at: Int) raises -> Float64:
        """Return a big-endian 32-bit float.

        Args:
            at: The byte.

        Returns:
            The value.

        Raises:
            Error: If it runs past the end.
        """
        return Float64(bitcast[DType.float32](self.word(at)))

    def int(self, at: Int) raises -> Int:
        """Return a big-endian 32-bit signed integer.

        Args:
            at: The byte.

        Returns:
            The value.

        Raises:
            Error: If it runs past the end.
        """
        return Int(bitcast[DType.int32](self.word(at)))

    def line_end(self, start: Int) raises -> Int:
        """Return where three.js's `findString` stops: the next line feed.

        Args:
            start: Where the line starts.

        Returns:
            The line feed's byte.

        Raises:
            Error: If no line feed follows, where three.js never stops.
        """
        var at = start
        while at < len(self.bytes) and self.bytes[at] != 10:
            at += 1
        if at >= len(self.bytes):
            raise Error(
                "VTK: the line at byte " + String(start) + " never ends"
            )
        return at


def _latin1(bytes: Span[UInt8, _]) -> List[Int]:
    """Return bytes as `String.fromCharCode` reads each one.

    Args:
        bytes: The bytes.

    Returns:
        One code unit each.
    """
    var out = List[Int](capacity=len(bytes))
    for b in bytes:
        out.append(Int(b))
    return out^


def _count(line: List[Int], word: Int, what: String) raises -> Int:
    """Return `parseInt( line.split( ' ' )[ word ], 10 )` as a count.

    Args:
        line: The line.
        word: Which word.
        what: The section, for the message.

    Returns:
        The count.

    Raises:
        Error: If it is not a number, where three.js reads for ever.
    """
    var text = _word(line, word)
    var value = nan[DType.float64]()
    if Bool(text):
        value = js_parse_int(text.value())
    if isnan(value):
        raise Error("VTK: a " + what + " line has no count")
    return Int(value)


def parse_vtk_binary(bytes: List[UInt8]) raises -> BufferGeometry:
    """Read a legacy VTK binary file, three.js's `parseBinary`.

    Args:
        bytes: The file.

    Returns:
        The geometry.

    Raises:
        Error: If the `DATASET` is not `POLYDATA`, a line never ends, a
            count is not a number, a value runs past the end, an index
            array would have a negative length, or an index is past the
            points.
    """
    var file = _Binary(bytes.copy())
    var points = List[Float64]()
    var normals = List[Float64]()
    var indices = List[Float64]()
    var has_points = False
    var has_normals = False
    var has_index = False
    var index = 0
    while True:
        var end = file.line_end(index)
        var line = _latin1(Span(file.bytes)[index:end])
        var next = end + 1
        if _starts(line, "DATASET"):
            var dataset = _second_word(line)
            if dataset != "POLYDATA":
                raise Error("Unsupported DATASET type: " + dataset)
        elif _starts(line, "POINTS"):
            var n = _count(line, 1, "POINTS")
            _ = _to_index(Float64(n) * 3, "the points")
            points = List[Float64]()
            has_points = True
            for k in range(n * 3):
                points.append(file.float(next + k * 4))
            next += n * 12 + 1
        elif _starts(line, "TRIANGLE_STRIPS") or _starts(line, "POLYGONS"):
            var strip_kind = _starts(line, "TRIANGLE_STRIPS")
            var cells = _count(line, 1, "cell")
            var size = _count(line, 2, "cell")
            var length = _to_index(Float64(3 * size - 9 * cells), "the index")
            indices = List[Float64](length=length, fill=0)
            has_index = True
            var slot = 0
            var at = next
            for _ in range(cells):
                var count = file.int(at)
                at += 4
                var cell = List[Float64]()
                for _ in range(count):
                    cell.append(_to_uint32(Float64(file.int(at))))
                    at += 4
                for j in range(count - 2):
                    var corners: List[Int]
                    if strip_kind:
                        corners = [j, j + 2, j + 1] if j % 2 == 1 else [
                            j,
                            j + 1,
                            j + 2,
                        ]
                    else:
                        corners = [0, j + 1, j + 2]
                    for c in corners:  # pragma: no branch
                        if slot < length:
                            indices[slot] = cell[c]
                        slot += 1
            next += size * 4 + 1
        elif _starts(line, "POINT_DATA"):
            var n = _count(line, 1, "POINT_DATA")
            _ = _to_index(Float64(n) * 3, "the normals")
            # three.js takes the next line to start the normals.
            next = file.line_end(next) + 1
            normals = List[Float64]()
            has_normals = True
            for k in range(n * 3):
                normals.append(file.float(next + k * 4))
            next += n * 12
        index = next
        if index >= len(file.bytes):
            break
    return _typed_geometry(
        points, normals, indices, has_points, has_normals, has_index
    )


# --- XML ---------------------------------------------------------------------


def _only(document: XmlDocument, parent: Int, name: String) raises -> Int:
    """Return the child of a name, as three.js's `xmlToJson` gives it.

    Args:
        document: The document.
        parent: The element.
        name: The child's name, as written.

    Returns:
        The one child of the name, `NO_ELEMENT` when there is none, or
        `_MANY` when there are more, which `xmlToJson` makes an array.
    """
    var found = NO_ELEMENT
    for child in document.children(parent):
        if document.name(child) == name:
            if found != NO_ELEMENT:
                return _MANY
            found = child
    return found


def _attribute_of(
    document: XmlDocument, element: Int, name: String
) raises -> Optional[String]:
    """Return an attribute, trimmed as `xmlToJson` trims it.

    Args:
        document: The document.
        element: The element.
        name: The attribute.

    Returns:
        Its value, or none.
    """
    if not document.has_attribute(element, name):
        return None
    var units = js_units(document.attribute(element, name))
    var kept = js_trim(units)
    return js_string(kept, 0, len(kept))


def _has_attributes(document: XmlDocument, element: Int) -> Bool:
    """Return True if an element has any attribute, which three.js's
    `xml.attributes.length > 0` asks.

    Args:
        document: The document.
        element: The element.

    Returns:
        Whether it has one.
    """
    return len(document.elements[element].attribute_names) > 0


def _needs_attributes(document: XmlDocument, element: Int, what: String) raises:
    """Refuse an element with no attributes, where three.js reads one.

    Args:
        document: The document.
        element: The element.
        what: What it is, for the message.

    Raises:
        Error: If it has none, as three.js throws a `TypeError`.
    """
    if not _has_attributes(document, element):
        raise Error("VTK: a " + what + " has no attributes")


def _relative(value: Float64, length: Int) -> Int:
    """Return a `slice` bound as JavaScript resolves it: NaN is zero, a
    negative one counts from the end, and it is clamped to the length.

    Args:
        value: The bound.
        length: The length sliced.

    Returns:
        The place.
    """
    if isnan(value):
        return 0
    var n = Float64(length)
    var t = value if isinf(value) else trunc(value)
    if t < 0:
        return Int(max(n + t, 0))
    return Int(min(t, n))


def _js_slice(
    units: List[Int], start: Optional[String], end: Optional[String]
) -> List[Int]:
    """Return JavaScript's `text.slice( start, end )` with string bounds.

    Args:
        units: The text.
        start: The start as the attribute gives it, or none for zero.
        end: The end as the attribute gives it, or none for the length.

    Returns:
        The part.
    """
    var a = 0
    if Bool(start):
        a = _relative(js_string_to_number(start.value()), len(units))
    var b = len(units)
    if Bool(end):
        b = _relative(js_string_to_number(end.value()), len(units))
    if b <= a:
        return List[Int]()
    return js_part(units, a, b)


def _look(units: List[Int], k: Int) -> Int:
    """Return three.js's `revLookup` of a character: its base64 or
    base64url value, and zero for any other, as `undefined` shifts.

    Args:
        units: The text.
        k: Which character, inside the text.

    Returns:
        Its six bits.
    """
    var u = units[k]
    if u >= 65 and u <= 90:
        return u - 65
    if u >= 97 and u <= 122:
        return u - 71
    if u >= 48 and u <= 57:
        return u + 4
    if u == 43 or u == 45:
        return 62
    if u == 47 or u == 95:
        return 63
    return 0


def _base64(units: List[Int]) raises -> List[UInt8]:
    """Return three.js's `Base64toByteArray`: base64 or base64url, with
    a character outside both read as zero.

    Args:
        units: The text.

    Returns:
        The bytes.

    Raises:
        Error: If the length is not a multiple of four, as three.js
            throws.
    """
    var n = len(units)
    if n % 4 > 0:
        raise Error("Invalid string. Length must be a multiple of 4")
    # The text is not empty, so it has four characters at least.
    var holders = 0
    if units[n - 2] == 61:
        holders = 2
    elif units[n - 1] == 61:
        holders = 1
    var length = n * 3 // 4 - holders
    var out = List[UInt8](capacity=length)
    var body = n - 4 if holders > 0 else n
    var i = 0
    while i < body:
        var tmp = (
            (_look(units, i) << 18)
            | (_look(units, i + 1) << 12)
            | (_look(units, i + 2) << 6)
            | _look(units, i + 3)
        )
        out.append(UInt8((tmp >> 16) & 0xFF))
        out.append(UInt8((tmp >> 8) & 0xFF))
        out.append(UInt8((tmp) & 0xFF))
        i += 4
    if holders == 2:
        out.append(
            UInt8(((_look(units, i) << 2) | (_look(units, i + 1) >> 4)) & 0xFF)
        )
    elif holders == 1:
        var tmp = (
            (_look(units, i) << 10)
            | (_look(units, i + 1) << 4)
            | (_look(units, i + 2) >> 2)
        )
        out.append(UInt8((tmp >> 8) & 0xFF))
        out.append(UInt8((tmp) & 0xFF))
    return out^


def _typed(
    bytes: Span[UInt8, _], type: String, what: String
) raises -> List[Float64]:
    """Return a buffer read as a little-endian `Float32Array` or
    `Int32Array`.

    Args:
        bytes: The buffer.
        type: `Float32`, or `Int32` or `Int64`.
        what: The array, for the message.

    Returns:
        The values.

    Raises:
        Error: If the length is not a multiple of four, as three.js
            throws a `RangeError`.
    """
    if len(bytes) % 4 != 0:
        raise Error("VTK: " + what + " is not a whole number of values")
    var out = List[Float64](capacity=len(bytes) // 4)
    for k in range(0, len(bytes), 4):
        var bits = (
            UInt32(bytes[k])
            | (UInt32(bytes[k + 1]) << 8)
            | (UInt32(bytes[k + 2]) << 16)
            | (UInt32(bytes[k + 3]) << 24)
        )
        if type == "Float32":
            out.append(Float64(bitcast[DType.float32](bits)))
        else:
            out.append(Float64(bitcast[DType.int32](bits)))
    return out^


def _low_halves(values: List[Float64]) -> List[Float64]:
    """Return every other value from the first, as three.js keeps an
    `Int64` array's low halves.

    Args:
        values: The 32-bit halves.

    Returns:
        The low halves.
    """
    var out = List[Float64]()
    for k in range(0, len(values), 2):
        out.append(values[k])
    return out^


def _header_value(bytes: List[UInt8], at: Int, width: Int) -> Int:
    """Return a header value as three.js reads it: its first byte, and
    each byte after it up to `width - 1`, shifted and joined with
    JavaScript's 32-bit `<<` and `|`. A byte past the end is `undefined`,
    which those make zero.

    Args:
        bytes: The decoded text.
        at: Where the value starts.
        width: The header's integer width.

    Returns:
        The value. With no width every value is the first byte's, as
        three.js reads it.
    """
    var inside = at < len(bytes)
    var value = Int(bytes[at]) if inside else 0
    for i in range(1, width - 1):
        var byte = 0
        if at + i < len(bytes):
            byte = Int(bytes[at + i])
        # JavaScript shifts by the count modulo 32, in 32 bits.
        var shifted = _to_int32(Float64(byte << ((8 * i) % 32)))
        value = Int(
            _to_int32(
                Float64(
                    Int(_to_uint32(Float64(value))) | Int(_to_uint32(shifted))
                )
            )
        )
    return value


def _inflated(block: Span[UInt8, _]) raises -> List[UInt8]:
    """Return fflate's `unzlibSync`: the zlib header checked, the adler
    left unread.

    Args:
        block: The zlib stream.

    Returns:
        The bytes.

    Raises:
        Error: If the header is not zlib's, names a dictionary, or the
            stream is malformed.
    """
    var bad = (
        len(block) < 2
        or (block[0] & 15) != 8
        or (block[0] >> 4) > 7
        or ((Int(block[0]) << 8) | Int(block[1])) % 31 != 0
    )
    if bad:
        raise Error("invalid zlib data")
    if (block[1] & 32) != 0:
        raise Error("invalid zlib data: preset dictionaries not supported")
    var copy = List[UInt8](capacity=len(block))
    for b in block:  # pragma: no branch
        copy.append(b)
    return inflate(copy, 2)


def _data_array(
    document: XmlDocument,
    element: Int,
    text: List[Int],
    binary: Bool,
    compressed: Bool,
    width: Int,
) raises -> Optional[List[Float64]]:
    """Return three.js's `parseDataArray`: a data array's values.

    Args:
        document: The document.
        element: The `DataArray`.
        text: Its text.
        binary: Whether it is base64, by its `format` or as appended data.
        compressed: Whether the file names a `compressor`.
        width: The header's integer width: 8, 4, or 0 when the file
            names neither.

    Returns:
        The values, or none for a type three.js does not read.

    Raises:
        Error: For base64 whose length is not a multiple of four, a
            compressed header cut short, a zlib block that is malformed,
            or a buffer that is not whole 32-bit values.
    """
    var type = _attribute_of(document, element, "type").or_else("")
    var known = type == "Float32" or type == "Int32" or type == "Int64"
    if binary and compressed:
        var bytes = _base64(text)
        if not known:
            return None
        # Text of a multiple of four characters is a byte at least.
        var values = List[Float64]()
        var blocks = _header_value(bytes, 0, width)
        var header = (blocks + 3) * width
        # JavaScript's `%` keeps the sign, so a negative header is not
        # padded.
        if header > 0 and header % 3 > 0:
            header += 3 - header % 3
        var offsets: List[Int] = [header]
        for i in range(blocks):
            var size = _header_value(bytes, i * width + 3 * width, width)
            offsets.append(offsets[len(offsets) - 1] + size)
        for i in range(len(offsets) - 1):
            var a = _relative(Float64(offsets[i]), len(bytes))
            var b = _relative(Float64(offsets[i + 1]), len(bytes))
            var data = _inflated(Span(bytes)[a : max(a, b)])
            values.extend(_typed(data, type, "a compressed block"))
        if type == "Int64":
            return _low_halves(values)
        return values^
    var values: List[Float64]
    if binary:
        var bytes = _base64(text)
        var cut = min(width, len(bytes))
        if not known:
            return None
        values = _typed(Span(bytes)[cut:], type, "a data array")
        if type == "Int64":
            values = _low_halves(values)
        return values^
    if not known:
        return None
    values = List[Float64]()
    # The text is trimmed, so each run of spaces has a word after it.
    var k = 0
    while k < len(text):
        while is_js_space(text[k]):
            k += 1
        var start = k
        while k < len(text) and not is_js_space(text[k]):
            k += 1
        var number = js_string_to_number(js_string(text, start, k))
        if type == "Float32":
            values.append(Float64(Float32(number)))
        else:
            values.append(_to_int32(number))
    return values^


struct _Array(Copyable, Movable):
    """A `DataArray` as three.js holds it: its element, and its values
    once read."""

    var element: Int
    # The text: its own, or its part of the appended data.
    var text: List[Int]
    var has_text: Bool
    var binary: Bool
    var values: Optional[List[Float64]]

    def __init__(out self, element: Int):
        """Start with no text and no values.

        Args:
            element: The `DataArray`.
        """
        self.element = element
        self.text = List[Int]()
        self.has_text = False
        self.binary = False
        self.values = None


def _read_values(array: _Array, what: String) raises -> List[Float64]:
    """Return a data array's values where three.js copies them.

    Args:
        array: The array.
        what: What they are, for the message.

    Returns:
        The values.

    Raises:
        Error: If there are none, as three.js throws a `TypeError`.
    """
    if not Bool(array.values):
        raise Error("VTK: the " + what + " array has no values")
    return array.values.value().copy()


def _filled(
    values: List[Float64], length: Int, what: String
) raises -> List[Float64]:
    """Return a `Float32Array` of a length with values set into it.

    Args:
        values: The values.
        length: The array's length.
        what: What it holds, for the message.

    Returns:
        The values then zeros, as `Float32` holds them.

    Raises:
        Error: If the values are longer, as `set` throws a `RangeError`.
    """
    if len(values) > length:
        raise Error("VTK: " + what + " hold more values than their count")
    var out = List[Float64](capacity=length)
    for value in values:
        out.append(Float64(Float32(value)))
    while len(out) < length:
        out.append(0)
    return out^


def _stored(conn: List[Int], at: Int) -> Float64:
    """Return a connectivity entry as a `Uint32Array` stores it.

    Args:
        conn: The connectivity.
        at: Which entry. It is inside the connectivity: the index holds
            `3 * len(conn) - 6 * count` entries, so its triangles read no
            further than entry `len(conn) - 1`.

    Returns:
        The entry.
    """
    return _to_uint32(Float64(conn[at]))


def _cells(
    connectivity: List[Float64],
    offsets: List[Float64],
    count: Float64,
    strips: Bool,
) raises -> List[Float64]:
    """Return three.js's index for `Strips` or `Polys`, cut as its loops
    cut them.

    Args:
        connectivity: The points of each cell, end to end.
        offsets: Where each cell ends.
        count: `NumberOfStrips` or `NumberOfPolys`.
        strips: True for strips, False for polygons.

    Returns:
        The index as a `Uint32Array` holds it.

    Raises:
        Error: If the index would have a negative length.
    """
    var conn = List[Int]()
    for value in connectivity:
        conn.append(Int(_to_int32(value)))
    var ends = List[Int]()
    for value in offsets:
        ends.append(Int(_to_int32(value)))
    var n = Int(min(count, Float64(1 << 40)))
    var size = n + len(conn)
    var length = _to_index(Float64(3 * size - 9 * n), "the index")
    var out = List[Float64](length=length, fill=0)
    var slot = 0
    # A cell past the offsets reads undefined, and its loops do not run.
    var cells = min(n, len(ends))
    var start = 0
    for i in range(cells):
        var end = ends[i]
        var before = ends[i - 1] if i > 0 else 0
        if strips:
            # three.js reads from the start of the connectivity; its loop
            # bound drops `before` after the first point.
            var points = 0
            if end > 0:
                points = max(1, end - before) if i > 0 else end
            var triangles = 0
            if end > 2:
                triangles = max(1, end - before - 2) if i > 0 else end - 2
            for j in range(triangles):
                if slot >= length:
                    break
                var corners = [j, j + 2, j + 1] if j % 2 == 1 else [
                    j,
                    j + 1,
                    j + 2,
                ]
                # The length is a multiple of three: a triangle that starts
                # inside it ends inside it.
                for c in corners:  # pragma: no branch
                    out[slot] = _stored(conn, c) if c < points else 0
                    slot += 1
        else:
            var points = max(end - before, 0)
            for j in range(1, points - 1):
                if slot >= length:
                    break
                for c in [0, j, j + 1]:  # pragma: no branch
                    out[slot] = _stored(conn, start + c)
                    slot += 1
            start += points
    return out^


def _slot_of(
    document: XmlDocument,
    mut arrays: List[_Array],
    mut slots: Dict[Int, Int],
    element: Int,
) raises -> Int:
    """Return where a `DataArray` is held, holding it the first time.

    Args:
        document: The document.
        arrays: The arrays held so far.
        slots: Each held array's place, by element.
        element: The `DataArray`.

    Returns:
        Its place in `arrays`.
    """
    if element not in slots:
        var array = _Array(element)
        var own = js_trim(js_units(document.text(element)))
        if len(own) > 0:
            array.text = own^
            array.has_text = True
        array.binary = (
            _attribute_of(document, element, "format").or_else("") == "binary"
        )
        slots[element] = len(arrays)
        arrays.append(array^)
    return slots[element]


def parse_vtk_xml(text: String) raises -> BufferGeometry:
    """Read a VTK XML poly data file, three.js's `parseXML`.

    Args:
        text: The file.

    Returns:
        The geometry.

    Raises:
        Error: If the text is not XML, the root has no `PolyData`, and
            for anything the module docstring lists.
    """
    var document = parse_xml(text)
    var root = document.root()
    var arrays = List[_Array]()
    # Each `DataArray` read, by element.
    var slots = Dict[Int, Int]()

    var poly_data = _only(document, root, "PolyData")
    var appended = _only(document, root, "AppendedData")
    if appended != NO_ELEMENT:
        if appended == _MANY:
            raise Error("VTK: the appended data has no text")
        var all = js_trim(js_units(document.text(appended)))
        if len(all) == 0:
            raise Error("VTK: the appended data has no text")
        var data = js_part(all, 1, len(all))
        if poly_data < 0:
            raise Error("VTK: the file has no one PolyData")
        var piece = _only(document, poly_data, "Piece")
        if piece == NO_ELEMENT:
            raise Error("VTK: the PolyData has no Piece")
        if piece != _MANY:
            var order: List[String] = [
                "PointData",
                "CellData",
                "Points",
                "Verts",
                "Lines",
                "Strips",
                "Polys",
            ]
            var elements = List[Int]()
            var offsets = List[Optional[String]]()
            for name in order:  # pragma: no branch
                var section = _only(document, piece, name)
                if section < 0:
                    continue
                for child in document.children_named(section, "DataArray"):
                    _needs_attributes(document, child, "DataArray")
                    elements.append(child)
                    offsets.append(_attribute_of(document, child, "offset"))
            for k in range(len(elements)):
                var at = _slot_of(document, arrays, slots, elements[k])
                # The last, or one with no `offset`, runs to the end.
                var next: Optional[String] = None
                if k + 1 < len(offsets):
                    next = offsets[k + 1]
                arrays[at].text = _js_slice(data, offsets[k], next)
                arrays[at].has_text = True
                arrays[at].binary = True
    if poly_data == NO_ELEMENT:
        raise Error("Unsupported DATASET type")
    if poly_data == _MANY:
        raise Error("VTK: the file has more than one PolyData")
    var piece = _only(document, poly_data, "Piece")
    if piece == NO_ELEMENT:
        raise Error("VTK: the PolyData has no Piece")
    _needs_attributes(document, root, "VTKFile")
    var compressed = document.has_attribute(root, "compressor")
    var header_type = _attribute_of(document, root, "header_type").or_else("")
    var width = 8 if header_type == "UInt64" else (
        4 if header_type == "UInt32" else 0
    )
    var points = List[Float64]()
    var normals = List[Float64]()
    var indices = List[Float64]()
    var has_points = False
    var has_normals = False
    var has_index = False
    if piece == _MANY:
        raise Error("VTK: the file has no cells to index")
    for name in [
        String("PointData"),
        "Points",
        "Strips",
        "Polys",
    ]:  # pragma: no branch
        var section = _only(document, piece, name)
        if section < 0:
            continue
        var children = document.children_named(section, "DataArray")
        if len(children) == 0:
            continue
        var at = List[Int]()
        for child in children:  # pragma: no branch
            var k = _slot_of(document, arrays, slots, child)
            at.append(k)
            if arrays[k].has_text and len(arrays[k].text) > 0:
                _needs_attributes(document, child, "DataArray")
                arrays[k].values = _data_array(
                    document,
                    child,
                    arrays[k].text,
                    arrays[k].binary,
                    compressed,
                    width,
                )
        _needs_attributes(document, piece, "Piece")
        if name == "PointData":
            var count = js_parse_int(
                _attribute_of(document, piece, "NumberOfPoints").or_else(
                    "undefined"
                )
            )
            _needs_attributes(document, section, "PointData")
            var wanted = _attribute_of(document, section, "Normals")
            if count > 0:
                for k in at:  # pragma: no branch
                    ref array = arrays[k]
                    _needs_attributes(document, array.element, "DataArray")
                    var named = _attribute_of(document, array.element, "Name")
                    var same = (not Bool(wanted) and not Bool(named)) or (
                        Bool(wanted)
                        and Bool(named)
                        and wanted.value() == named.value()
                    )
                    if same:
                        var components = _attribute_of(
                            document, array.element, "NumberOfComponents"
                        )
                        var each = nan[DType.float64]()
                        if Bool(components):
                            each = js_string_to_number(components.value())
                        has_normals = True
                        normals = _filled(
                            _read_values(array, "normals"),
                            _to_index(count * each, "the normals"),
                            "the normals",
                        )
        elif name == "Points":
            var count = js_parse_int(
                _attribute_of(document, piece, "NumberOfPoints").or_else(
                    "undefined"
                )
            )
            if count > 0:
                if len(at) > 1:
                    raise Error("VTK: the Points have more than one DataArray")
                ref array = arrays[at[0]]
                _needs_attributes(document, array.element, "DataArray")
                var components = _attribute_of(
                    document, array.element, "NumberOfComponents"
                )
                var each = nan[DType.float64]()
                if Bool(components):
                    each = js_string_to_number(components.value())
                has_points = True
                points = _filled(
                    _read_values(array, "points"),
                    _to_index(count * each, "the points"),
                    "the points",
                )
        else:
            var key = "NumberOfStrips" if name == "Strips" else "NumberOfPolys"
            var count = js_parse_int(
                _attribute_of(document, piece, key).or_else("undefined")
            )
            if count > 0:
                if len(at) < 2:
                    raise Error(
                        "VTK: the " + name + " need a connectivity and offsets"
                    )
                has_index = True
                indices = _cells(
                    _read_values(arrays[at[0]], "connectivity"),
                    _read_values(arrays[at[1]], "offsets"),
                    count,
                    name == "Strips",
                )
    return _typed_geometry(
        points, normals, indices, has_points, has_normals, has_index
    )


def parse_vtk(bytes: List[UInt8]) raises -> BufferGeometry:
    """Read a VTK file's bytes, three.js's `VTKLoader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The geometry.

    Raises:
        Error: If the file is shorter than 250 bytes or its third line is
            past them, as three.js throws, and for anything the parser of
            its kind refuses.
    """
    if len(bytes) < VTK_META_BYTES:
        raise Error(
            "VTK: a file shorter than 250 bytes, which three.js refuses"
        )
    var lines = List[List[UInt8]]()
    var line = List[UInt8]()
    for k in range(VTK_META_BYTES):  # pragma: no branch
        if bytes[k] == 10:
            lines.append(line^)
            line = List[UInt8]()
        else:
            line.append(bytes[k])
    lines.append(line^)
    if String(unsafe_from_utf8=lines[0]).find("xml") >= 0:
        return parse_vtk_xml(_decoded(bytes))
    if len(lines) < 3:
        raise Error("VTK: the third line is past the first 250 bytes")
    if String(unsafe_from_utf8=lines[2]).find("ASCII") >= 0:
        return parse_vtk_ascii(_decoded(bytes))
    return parse_vtk_binary(bytes)


def read_vtk(path: String) raises -> BufferGeometry:
    """Read a VTK file.

    Args:
        path: The file.

    Returns:
        What `parse_vtk` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_vtk`
            refuses.
    """
    return parse_vtk(Path(path).read_bytes())
