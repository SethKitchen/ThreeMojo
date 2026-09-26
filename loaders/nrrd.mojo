# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""NRRD volumes, from three.js `examples/jsm/loaders/NRRDLoader.js`.

An NRRD file is a text header, a blank line, and the data. `parse_nrrd`
reads it into an `objects.volume.Volume` as three.js's `parse` does.

**The header.** A line that holds `NRRD` and a digit marks the file. A
line that does not start with `#` and holds a `:` is a field: the text
before its last `:`, and the text after it, both trimmed. three.js reads
`type`, `endian`, `encoding`, `dimension`, `sizes`, `space`,
`space origin`, `space directions` and `spacings`, and `fields` keeps the
others. With no `space directions`, the directions are the axes, scaled
by the `spacings` that are numbers.

**The data.** A `gz` encoding is gunzipped, as fflate's `gunzipSync`
does it. `ascii`, `text`, `txt` and `hex` are words, read with `parseInt`
in base 10 or 16, or with `parseFloat` for `float` and `double`, into as
many values as the `sizes` hold. `raw` is the bytes after the header.

**The volume.** The values, their range, the lengths from the `sizes`,
the axis order and the spacing from the directions, and the matrix from
voxel indices to RAS space: the directions times a flip for a
`left-posterior-superior` or `left-anterior-superior` space.

**Where three.js's quirks are kept.** three.js cuts the header one
character short: the last line before the blank line loses its last
character. So `encoding: raw` there reads `ra`. An encoding three.js
does not know reads the whole file, header and all, as the data. The
`endian` field is read but not applied: the data is little-endian.

**What is refused.** What three.js throws on: a file with no blank line
after the header, or that is not NRRD; a `bz2` or `bzip2` encoding; a
type it does not know, or none; no encoding; a `space origin` with no
`(`; `space directions` with no `( )`, or fewer than three of them;
gzip data that is not gzip; and data that is not whole values of its
type.
"""

from loaders.js_number import js_parse_float, js_parse_int
from loaders.js_text import is_js_space, js_part, js_string, js_trim
from math.matrix4 import Matrix4
from objects.volume import Volume, volume_values
from render.inflate import inflate
from std.math import floor, isinf, isnan, nan, sqrt, trunc
from std.pathlib import Path

# The longest data this port makes. three.js makes any length the browser
# allows.
comptime MAX_NRRD_VALUES = 1 << 28


struct NrrdHeader(Copyable, Movable):
    """The fields of an NRRD header, as three.js's `headerObject` holds
    them."""

    var is_nrrd: Bool
    # The `type` as written, and the typed array three.js reads it into,
    # by the `Volume` constructor's name: `Uint8`, `Int8`, `Int16`,
    # `Uint16`, `Int32`, `Uint32`, `Float32` or `Float64`.
    var type: Optional[String]
    var array_type: Optional[String]
    var endian: Optional[String]
    var encoding: Optional[String]
    # The `dimension`, NaN when it is not a number.
    var dim: Optional[Float64]
    # The `sizes`, NaN for a word that is not a number.
    var sizes: Optional[List[Float64]]
    var space: Optional[String]
    # The `space origin`'s words between the parentheses, not trimmed.
    var space_origin: Optional[List[String]]
    # Each direction of `space directions`, or the axes when none.
    var vectors: Optional[List[List[Float64]]]
    var spacings: Optional[List[Float64]]
    # Every other field, name and value, in file order.
    var field_names: List[String]
    var field_values: List[String]

    def __init__(out self):
        """Start with no fields."""
        self.is_nrrd = False
        self.type = None
        self.array_type = None
        self.endian = None
        self.encoding = None
        self.dim = None
        self.sizes = None
        self.space = None
        self.space_origin = None
        self.vectors = None
        self.spacings = None
        self.field_names = List[String]()
        self.field_values = List[String]()


def _array_type(type: String) raises -> String:
    """Return the typed array three.js reads a `type` into.

    Args:
        type: The `type` field.

    Returns:
        The `Volume` constructor's name for it.

    Raises:
        Error: For a type three.js does not know.
    """
    var table: List[List[String]] = [
        ["Uint8", "uchar", "unsigned char", "uint8", "uint8_t"],
        ["Int8", "signed char", "int8", "int8_t"],
        [
            "Int16",
            "short",
            "short int",
            "signed short",
            "signed short int",
            "int16",
            "int16_t",
        ],
        [
            "Uint16",
            "ushort",
            "unsigned short",
            "unsigned short int",
            "uint16",
            "uint16_t",
        ],
        ["Int32", "int", "signed int", "int32", "int32_t"],
        ["Uint32", "uint", "unsigned int", "uint32", "uint32_t"],
        ["Float32", "float"],
        ["Float64", "double"],
    ]
    for row in table:  # pragma: no branch
        for k in range(1, len(row)):  # pragma: no branch
            if row[k] == type:
                return row[0]
    raise Error("Unsupported NRRD data type: " + type)


def _latin1(bytes: Span[UInt8, _]) -> List[Int]:
    """Return bytes as three.js's `_parseChars` reads each one: a code
    unit each.

    Args:
        bytes: The bytes.

    Returns:
        The code units.
    """
    var out = List[Int](capacity=len(bytes))
    for b in bytes:
        out.append(Int(b))
    return out^


def _words(units: List[Int]) -> List[String]:
    """Return JavaScript's `text.split( /\\s+/ )` of trimmed text.

    Args:
        units: The text, trimmed.

    Returns:
        The words; one empty word for an empty text.
    """
    var out = List[String]()
    var start = 0
    var k = 0
    while k < len(units):
        if is_js_space(units[k]):
            out.append(js_string(units, start, k))
            # The text is trimmed, so a word follows each run of spaces.
            while is_js_space(units[k]):
                k += 1
            start = k
        else:
            k += 1
    out.append(js_string(units, start, len(units)))
    return out^


def _find(units: List[Int], unit: Int, start: Int) -> Int:
    """Return where a code unit next is.

    Args:
        units: The text.
        unit: The code unit.
        start: Where to look from.

    Returns:
        Its index, or -1.
    """
    for k in range(start, len(units)):
        if units[k] == unit:
            return k
    return -1


def _is_nrrd_line(units: List[Int]) -> Bool:
    """Return three.js's `line.match( /NRRD\\d+/ )`.

    Args:
        units: The line.

    Returns:
        Whether `NRRD` and a digit are in it.
    """
    for k in range(len(units) - 4):
        var digit = units[k + 4] >= 48 and units[k + 4] <= 57
        if digit and js_string(units, k, k + 4) == "NRRD":
            return True
    return False


def parse_nrrd_header(text: List[Int]) raises -> NrrdHeader:
    """Read an NRRD header, three.js's `parseHeader`.

    Args:
        text: The header, a code unit a byte.

    Returns:
        The fields, with the directions set.

    Raises:
        Error: If no line marks the file NRRD, the encoding is `bz2` or
            `bzip2`, the type is unknown, the `space origin` has no `(`,
            or `space directions` has no `( )`.
    """
    var header = NrrdHeader()
    var start = 0
    while start <= len(text):
        var end = _find(text, 10, start)
        if end < 0:
            end = len(text)
        var stop = end
        # `split( /\r?\n/ )`: a carriage return before the line feed goes.
        if stop > start and end < len(text) and text[stop - 1] == 13:
            stop -= 1
        var line = List[Int]()
        for k in range(start, stop):
            line.append(text[k])
        start = end + 1
        if _is_nrrd_line(line):
            header.is_nrrd = True
            continue
        if len(line) > 0 and line[0] == 35:
            continue
        var colon = -1
        for k in range(len(line)):
            if line[k] == 58:
                colon = k
        if colon < 0:
            continue
        var name_units = js_trim(js_part(line, 0, colon))
        var data_units = js_trim(js_part(line, colon + 1, len(line)))
        var field = js_string(name_units, 0, len(name_units))
        var data = js_string(data_units, 0, len(data_units))
        if field == "type":
            header.array_type = _array_type(data)
            header.type = data
        elif field == "endian":
            header.endian = data
        elif field == "encoding":
            header.encoding = data
        elif field == "dimension":
            header.dim = js_parse_int(data)
        elif field == "sizes":
            var sizes = List[Float64]()
            for word in _words(data_units):  # pragma: no branch
                sizes.append(js_parse_int(word))
            header.sizes = sizes^
        elif field == "space":
            header.space = data
        elif field == "space origin":
            var open = _find(data_units, 40, 0)
            if open < 0:
                raise Error("NRRD: the space origin has no (")
            # `split( '(' )[ 1 ]` ends at a second `(`, and
            # `split( ')' )[ 0 ]` at the first `)` before it.
            var end = len(data_units)
            var second = _find(data_units, 40, open + 1)
            if second >= 0:
                end = second
            var close = _find(data_units, 41, open + 1)
            if close >= 0 and close < end:
                end = close
            var inside = js_string(data_units, open + 1, end)
            var origin = List[String]()
            for word in inside.split(","):  # pragma: no branch
                origin.append(String(word))
            header.space_origin = origin^
        elif field == "space directions":
            var vectors = List[List[Float64]]()
            var at = 0
            while True:
                var open = _find(data_units, 40, at)
                if open < 0:
                    break
                var close = _find(data_units, 41, open + 1)
                if close < 0:
                    break
                var vector = List[Float64]()
                for word in js_string(data_units, open + 1, close).split(
                    ","
                ):  # pragma: no branch
                    vector.append(js_parse_float(String(word)))
                vectors.append(vector^)
                at = close + 1
            if len(vectors) == 0:
                raise Error("NRRD: the space directions have no ( )")
            header.vectors = vectors^
        elif field == "spacings":
            var spacings = List[Float64]()
            for word in _words(data_units):  # pragma: no branch
                spacings.append(js_parse_float(word))
            header.spacings = spacings^
        else:
            header.field_names.append(field)
            header.field_values.append(data)
    if not header.is_nrrd:
        raise Error("Not an NRRD file")
    if Bool(header.encoding):
        var encoding = header.encoding.value()
        if encoding == "bz2" or encoding == "bzip2":
            raise Error("Bzip is not supported")
    if not Bool(header.vectors):
        var vectors: List[List[Float64]] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
        if Bool(header.spacings):
            var spacings = header.spacings.value().copy()
            for i in range(min(3, len(spacings))):  # pragma: no branch
                if not isnan(spacings[i]):
                    for j in range(3):  # pragma: no branch
                        vectors[i][j] *= spacings[i]
        header.vectors = vectors^
    return header^


def gunzip(bytes: Span[UInt8, _]) raises -> List[UInt8]:
    """Return fflate's `gunzipSync`: the first member of a gzip file,
    made as long as its trailer says.

    Args:
        bytes: The gzip file.

    Returns:
        The bytes, cut or padded with zeros to the trailer's length, as
        fflate's buffer of that length holds them.

    Raises:
        Error: If the header is not gzip's, the file is too short for its
            header and trailer, the stream is malformed, or the trailer's
            length is past `MAX_NRRD_VALUES`.
    """
    var n = len(bytes)
    var bad = n < 3 or bytes[0] != 31 or bytes[1] != 139 or bytes[2] != 8
    if bad:
        raise Error("invalid gzip data")
    # A byte past the end reads `undefined`, which `&` and `!` read as
    # zero and true.
    var flags = Int(bytes[3]) if n > 3 else 0
    var start = 10
    if Bool(flags & 4):
        var low = Int(bytes[10]) if n > 10 else 0
        var high = Int(bytes[11]) if n > 11 else 0
        start += (low | (high << 8)) + 2
    var names = ((flags >> 3) & 1) + ((flags >> 4) & 1)
    while names > 0:
        if start >= n or bytes[start] == 0:
            names -= 1
        start += 1
    start += flags & 2
    if start + 8 > n:
        raise Error("invalid gzip data")
    var length = (
        Int(bytes[n - 4])
        | (Int(bytes[n - 3]) << 8)
        | (Int(bytes[n - 2]) << 16)
        | (Int(bytes[n - 1]) << 24)
    )
    if length > MAX_NRRD_VALUES:
        raise Error("NRRD: the gzip data is longer than this port makes")
    var stream = List[UInt8](capacity=n - 8 - start)
    for k in range(start, n - 8):
        stream.append(bytes[k])
    var out = inflate(stream)
    while len(out) > length:
        _ = out.pop()
    while len(out) < length:
        out.append(0)
    return out^


def _typed(value: Float64, array_type: String) -> Float64:
    """Return a value as a typed array of a type stores it.

    Args:
        value: The value.
        array_type: The `Volume` constructor's name for the type.

    Returns:
        The stored value: wrapped for an integer type, NaN made zero, and
        rounded to `Float32` for `Float32`.
    """
    if array_type == "Float64":
        return value
    if array_type == "Float32":
        return Float64(Float32(value))
    if isnan(value) or isinf(value):
        return 0
    var bits = 8
    if array_type == "Int16" or array_type == "Uint16":
        bits = 16
    elif array_type == "Int32" or array_type == "Uint32":
        bits = 32
    var modulus = Float64(1 << bits)
    var t = trunc(value)
    var wrapped = t - floor(t / modulus) * modulus
    var signed = array_type.startswith("Int")
    if signed and wrapped >= modulus / 2:
        wrapped -= modulus
    return wrapped


def _parse_int_radix(word: List[Int], radix: Int) -> Float64:
    """Return JavaScript's `parseInt( word, radix )` for base 10 or 16.

    Args:
        word: The word, a code unit a byte, with no ASCII white space.
        radix: 10 or 16.

    Returns:
        The whole number at the start; NaN when there is none.
    """
    var k = 0
    # A no-break space is JavaScript white space; the others are not in a
    # word.
    while k < len(word) and word[k] == 0xA0:
        k += 1
    var negative = False
    if k < len(word) and (word[k] == 43 or word[k] == 45):
        negative = word[k] == 45
        k += 1
    var hex_prefix = (
        radix == 16
        and k + 1 < len(word)
        and word[k] == 48
        and (word[k + 1] | 32) == 120
    )
    if hex_prefix:
        k += 2
    var value = Float64(0)
    var digits = 0
    while k < len(word):
        var u = word[k]
        var digit = -1
        if u >= 48 and u <= 57:
            digit = u - 48
        elif radix == 16 and (u | 32) >= 97 and (u | 32) <= 102:
            digit = (u | 32) - 87
        if digit < 0:
            break
        value = value * Float64(radix) + Float64(digit)
        digits += 1
        k += 1
    if digits == 0:
        return nan[DType.float64]()
    return -value if negative else value


def _text_values(
    data: Span[UInt8, _], header: NrrdHeader, array_type: String
) raises -> List[Float64]:
    """Return three.js's `parseDataAsText`: each word as a value, into as
    many values as the sizes hold.

    Args:
        data: The bytes after the header.
        header: The header.
        array_type: The typed array the values go in.

    Returns:
        The values, zero where no word was.

    Raises:
        Error: If there are no `sizes`, or their product is negative or
            past `MAX_NRRD_VALUES`.
    """
    if not Bool(header.sizes):
        raise Error("NRRD: the header has no sizes")
    var product = Float64(1)
    for size in header.sizes.value():  # pragma: no branch
        product *= size
    var length = 0
    if not isnan(product):
        if product < 0 or product > Float64(MAX_NRRD_VALUES):
            raise Error("NRRD: the sizes hold no length this port makes")
        length = Int(product)
    var radix = 16 if header.encoding.value() == "hex" else 10
    var floating = array_type == "Float32" or array_type == "Float64"
    var out = List[Float64](length=length, fill=0)
    var at = 0
    var word = List[Int]()
    for k in range(len(data) + 1):  # pragma: no branch
        var b = Int(data[k]) if k < len(data) else 32
        var space = (b >= 9 and b <= 13) or b == 32
        if not space:
            word.append(b)
            continue
        if len(word) > 0:
            var value: Float64
            if floating:
                var start = 0
                while start < len(word) and word[start] == 0xA0:
                    start += 1
                value = js_parse_float(js_string(word, start, len(word)))
            else:
                value = _parse_int_radix(word, radix)
            if at < length:
                out[at] = _typed(value, array_type)
            at += 1
        word = List[Int]()
    return out^


def _component(vector: List[Float64], k: Int) -> Float64:
    """Return one number of a direction, as `Vector3.fromArray` reads it.

    Args:
        vector: The direction.
        k: Which number.

    Returns:
        The number, or NaN past the end, as `undefined` reads.
    """
    return vector[k] if k < len(vector) else nan[DType.float64]()


def parse_nrrd(bytes: List[UInt8]) raises -> Volume:
    """Read an NRRD file's bytes, three.js's `NRRDLoader.parse`.

    Args:
        bytes: The whole file.

    Returns:
        The volume.

    Raises:
        Error: For anything the module docstring lists.
    """
    var end = -1
    for i in range(1, len(bytes)):
        if bytes[i - 1] == 10 and bytes[i] == 10:
            end = i
            break
    if end < 0:
        raise Error("NRRD: no blank line ends the header")
    # three.js's `_parseChars( _bytes, 0, i - 2 )`: one character short.
    var header = parse_nrrd_header(_latin1(Span(bytes)[: max(end - 2, 0)]))
    var data = Span(bytes)[end + 1 :]
    if not Bool(header.encoding):
        raise Error("NRRD: the header has no encoding")
    var encoding = header.encoding.value()
    if not Bool(header.array_type):
        raise Error("NRRD: the header has no type")
    var array_type = header.array_type.value()
    var values: List[Float64]
    # three.js's `encoding.substring( 0, 2 ) === 'gz'`.
    if encoding.startswith("gz"):
        values = volume_values(gunzip(data), array_type)
    elif (
        encoding == "ascii"
        or encoding == "text"
        or encoding == "txt"
        or encoding == "hex"
    ):
        values = _text_values(data, header, array_type)
    elif encoding == "raw":
        values = volume_values(data, array_type)
    else:
        # three.js takes the buffer under the data, which is the whole
        # file.
        values = volume_values(Span(bytes), array_type)
    var volume = Volume()
    volume.data = values^
    var limits = volume.compute_min_max()
    volume.window_low = limits[0]
    volume.window_high = limits[1]
    var sizes = header.sizes.value().copy() if Bool(header.sizes) else List[
        Float64
    ]()
    var dimensions = List[Float64]()
    for k in range(3):  # pragma: no branch
        dimensions.append(sizes[k] if k < len(sizes) else nan[DType.float64]())
    volume.dimensions = dimensions.copy()
    volume.x_length = dimensions[0]
    volume.y_length = dimensions[1]
    volume.z_length = dimensions[2]
    var vectors = header.vectors.value().copy()
    if len(vectors) < 3:
        raise Error("NRRD: the space directions are fewer than three")

    var found = List[Int]()
    for axis in range(3):  # pragma: no branch
        var index = -1
        for v in range(len(vectors)):  # pragma: no branch
            if _component(vectors[v], axis) != 0:
                index = v
                break
        found.append(index)
    var distinct = (
        found[0] != found[1] and found[0] != found[2] and found[1] != found[2]
    )
    if distinct:
        var order = List[String]()
        var names: List[String] = ["x", "y", "z"]
        for axis in range(3):  # pragma: no branch
            var at = found[axis]
            if at < 0:
                continue
            while len(order) <= at:
                order.append("")
            order[at] = names[axis]
        volume.axis_order = order^
    var spacing = List[Float64]()
    for v in range(3):  # pragma: no branch
        var x = _component(vectors[v], 0)
        var y = _component(vectors[v], 1)
        var z = _component(vectors[v], 2)
        spacing.append(sqrt(x * x + y * y + z * z))
    volume.spacing = spacing.copy()
    var transition = Matrix4()
    var space = header.space.or_else("")
    if space == "left-posterior-superior":
        transition.set(-1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
    elif space == "left-anterior-superior":
        transition.set(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1)
    var matrix = Matrix4()
    matrix.set(
        Float32(_component(vectors[0], 0)),
        Float32(_component(vectors[1], 0)),
        Float32(_component(vectors[2], 0)),
        0,
        Float32(_component(vectors[0], 1)),
        Float32(_component(vectors[1], 1)),
        Float32(_component(vectors[2], 1)),
        0,
        Float32(_component(vectors[0], 2)),
        Float32(_component(vectors[1], 2)),
        Float32(_component(vectors[2], 2)),
        0,
        0,
        0,
        0,
        1,
    )
    matrix.multiply(transition)
    volume.matrix = matrix
    var inverse = matrix
    inverse.invert()
    volume.inverse_matrix = inverse
    volume.ras_dimensions = [
        floor(volume.x_length * spacing[0]),
        floor(volume.y_length * spacing[1]),
        floor(volume.z_length * spacing[2]),
    ]
    volume.lower_threshold = volume.min
    volume.upper_threshold = volume.max
    return volume^


def read_nrrd(path: String) raises -> Volume:
    """Read an NRRD file.

    Args:
        path: The file.

    Returns:
        What `parse_nrrd` gives.

    Raises:
        Error: If the file cannot be read, or for anything `parse_nrrd`
            refuses.
    """
    return parse_nrrd(Path(path).read_bytes())
