# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""USDC crate files, from three.js r186's
`examples/jsm/loaders/usd/USDCParser.js`.

`parse_usdc` reads a crate into a `UsdLayer`, as three.js's `parseData`
reads it into `{ specsByPath }`. A crate is OpenUSD's binary layer: a
bootstrap with the magic `PXR-USDC`, the version and where the table of
contents is; then the sections the table names. `TOKENS` holds the
strings, `STRINGS` indexes into them, `FIELDS` names each field and packs
its value, `FIELDSETS` lists the fields of each spec, `PATHS` holds the
path tree and `SPECS` ties a path to its fields.

**The compression.** From version 0.4.0 the sections are compressed.
`decompress_lz4` is OpenUSD's `TfFastCompression`: a chunk count, then
LZ4 blocks, which `lz4_decompress_block` expands. `decompress_integers32`
expands an LZ4 block into a common value, two bits of code for each
integer and the integers' differences in one, two or four bytes, which
`decode_integers32` sums. Arrays of integers and of floats are compressed
the same way, and floats can also be indices into a table.

**The values.** A value is a 64-bit `ValueRep`: a type, three flags and a
48-bit payload. A value that fits is inlined in the payload; any other is
at the payload's offset. `CrateType` names the type.

**Where three.js's quirks are kept.** Each is what three.js r186 does:

- An inlined `int` is read as unsigned, so -7 reads as 4294967289.
- An inlined `double` is read from float bits. An inlined `half`, and an
  inlined `double2`, `double3` or `double4`, read as the payload number.
- A `string` value that is not inlined is read as a token.
- A dictionary is always empty, as three.js's reader reads it.
- A reference, a payload and the other list operations but paths read
  as `null`, so a crate's references do not compose.
- An array of a type three.js does not read is empty, and a scalar of
  such a type is `null`.
- A compressed array of floats with an unknown code is zeros.

**What is refused.** What three.js throws on: a file that does not start
with `PXR-USDC`, a read past the end of the file, a payload offset past
the end, and an array of more than 2^31 - 1 elements. And where this
port holds less than three.js: a missing `TOKENS`, `FIELDS`, `FIELDSETS`,
`PATHS` or `SPECS` section; a spec type outside the known ones; time
samples whose times are not numbers; an LZ4 chunk past the end of its
input; a path tree that does not end; and a count past `MAX_COUNT` or
past what the file can hold.

A value of a type outside the known ones reads as three.js reads a type
it does not support: its payload when it is inlined, and `null` or an
empty array when it is not. A file of a version before 0.4.0 has path
headers that three.js reads one padding byte short, so its paths are
the wrong ones; this port reads them as three.js does.
"""

from loaders.usd_specs import (
    NO_VALUE,
    SpecType,
    USD_NULL,
    USD_NUMBERS,
    USD_OBJECT,
    USD_SAMPLES,
    UsdLayer,
    UsdSpec,
    UsdValue,
    usd_boolean,
    usd_number,
    usd_numbers,
    usd_string,
    usd_strings,
)
from std.math import inf, nan
from std.memory import bitcast


@fieldwise_init
struct CrateType(Equatable, ImplicitlyCopyable, Writable):
    """The type of a crate value, as a type rather than a bare int: the
    `TypeEnum` of three.js's parser and OpenUSD's `crateDataTypes.h`.

    The value is the number the file stores. `parse_usdc` refuses one
    that `is_valid` does not accept.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True for the sixty-one types, zero to sixty."""
        return self.value >= 0 and self.value <= 60


comptime CRATE_INVALID = CrateType(0)
comptime CRATE_BOOL = CrateType(1)
comptime CRATE_UCHAR = CrateType(2)
comptime CRATE_INT = CrateType(3)
comptime CRATE_UINT = CrateType(4)
comptime CRATE_INT64 = CrateType(5)
comptime CRATE_UINT64 = CrateType(6)
comptime CRATE_HALF = CrateType(7)
comptime CRATE_FLOAT = CrateType(8)
comptime CRATE_DOUBLE = CrateType(9)
comptime CRATE_STRING = CrateType(10)
comptime CRATE_TOKEN = CrateType(11)
comptime CRATE_ASSET_PATH = CrateType(12)
comptime CRATE_MATRIX2D = CrateType(13)
comptime CRATE_MATRIX3D = CrateType(14)
comptime CRATE_MATRIX4D = CrateType(15)
comptime CRATE_QUATD = CrateType(16)
comptime CRATE_QUATF = CrateType(17)
comptime CRATE_QUATH = CrateType(18)
comptime CRATE_VEC2D = CrateType(19)
comptime CRATE_VEC2F = CrateType(20)
comptime CRATE_VEC2H = CrateType(21)
comptime CRATE_VEC2I = CrateType(22)
comptime CRATE_VEC3D = CrateType(23)
comptime CRATE_VEC3F = CrateType(24)
comptime CRATE_VEC3H = CrateType(25)
comptime CRATE_VEC3I = CrateType(26)
comptime CRATE_VEC4D = CrateType(27)
comptime CRATE_VEC4F = CrateType(28)
comptime CRATE_VEC4H = CrateType(29)
comptime CRATE_VEC4I = CrateType(30)
comptime CRATE_DICTIONARY = CrateType(31)
comptime CRATE_TOKEN_LIST_OP = CrateType(32)
comptime CRATE_STRING_LIST_OP = CrateType(33)
comptime CRATE_PATH_LIST_OP = CrateType(34)
comptime CRATE_REFERENCE_LIST_OP = CrateType(35)
comptime CRATE_INT_LIST_OP = CrateType(36)
comptime CRATE_INT64_LIST_OP = CrateType(37)
comptime CRATE_UINT_LIST_OP = CrateType(38)
comptime CRATE_UINT64_LIST_OP = CrateType(39)
comptime CRATE_PATH_VECTOR = CrateType(40)
comptime CRATE_TOKEN_VECTOR = CrateType(41)
comptime CRATE_SPECIFIER = CrateType(42)
comptime CRATE_PERMISSION = CrateType(43)
comptime CRATE_VARIABILITY = CrateType(44)
comptime CRATE_VARIANT_SELECTION_MAP = CrateType(45)
comptime CRATE_TIME_SAMPLES = CrateType(46)
comptime CRATE_PAYLOAD = CrateType(47)
comptime CRATE_DOUBLE_VECTOR = CrateType(48)
comptime CRATE_LAYER_OFFSET_VECTOR = CrateType(49)
comptime CRATE_STRING_VECTOR = CrateType(50)
comptime CRATE_VALUE_BLOCK = CrateType(51)
comptime CRATE_VALUE = CrateType(52)
comptime CRATE_UNREGISTERED_VALUE = CrateType(53)
comptime CRATE_UNREGISTERED_VALUE_LIST_OP = CrateType(54)
comptime CRATE_PAYLOAD_LIST_OP = CrateType(55)
comptime CRATE_TIME_CODE = CrateType(56)
comptime CRATE_PATH_EXPRESSION = CrateType(57)
comptime CRATE_RELOCATES = CrateType(58)
comptime CRATE_SPLINE = CrateType(59)
comptime CRATE_ANIMATION_BLOCK = CrateType(60)

# The field set terminator, as a `Uint32Array` and an `Int32Array` hold it.
comptime _TERMINATOR = 0xFFFFFFFF
# The codes of a compressed float array.
comptime _FLOAT_AS_INTS = 0x69
comptime _FLOAT_TABLE = 0x74
# How many bytes an LZ4 chunk of several expands to.
comptime _CHUNK = 65536
# The most elements, paths, fields or specs this reader allocates for.
comptime MAX_COUNT = 1 << 26
# How deep time samples may nest before the reader refuses them.
comptime _MAX_DEPTH = 64


def is_crate(bytes: Span[UInt8, _]) -> Bool:
    """Return three.js's `isCrateFile`: the bytes start with `PXR-USDC`.

    Args:
        bytes: The file.

    Returns:
        Whether it is a crate.
    """
    if len(bytes) < 8:
        return False
    var magic: List[UInt8] = [0x50, 0x58, 0x52, 0x2D, 0x55, 0x53, 0x44, 0x43]
    for k in range(8):  # pragma: no branch
        if bytes[k] != magic[k]:
            return False
    return True


def lz4_decompress_block(
    input: List[UInt8],
    input_start: Int,
    input_end: Int,
    mut output: List[UInt8],
    output_start: Int,
    output_end: Int,
) -> Int:
    """Expand one LZ4 block, three.js's `lz4DecompressBlock`.

    Each sequence is a token, its literals and a match that copies from
    what is already written. A literal run or a match that would pass
    `output_end` stops where it is, as three.js's does, and a match of
    offset zero, or one that starts before the output, ends the block.

    Args:
        input: The compressed bytes.
        input_start: Where the block starts.
        input_end: Where it ends. It must be within `input`.
        output: Where the bytes go.
        output_start: Where the first byte goes.
        output_end: Where the output of this block must stop. It must be
            within `output`.

    Returns:
        Where the next byte would go.
    """
    var at = input_start
    var out = output_start
    while at < input_end:
        var token = Int(input[at])
        at += 1
        var literals = token >> 4
        if literals == 15:
            var more = 255
            while more == 255 and at < input_end:
                more = Int(input[at])
                at += 1
                literals += more
        if at + literals > input_end:
            literals = input_end - at
        for _ in range(literals):
            if out >= output_end:
                break
            output[out] = input[at]
            out += 1
            at += 1
        # The last sequence has no match.
        if at + 2 > input_end:
            break
        var offset = Int(input[at]) | (Int(input[at + 1]) << 8)
        at += 2
        if offset == 0:
            break
        var length = (token & 0x0F) + 4
        if length == 19:
            var more = 255
            while more == 255 and at < input_end:
                more = Int(input[at])
                at += 1
                length += more
        var start = out - offset
        if start < 0:
            break
        for i in range(length):
            if out >= output_end:
                break
            output[out] = output[start + i]
            out += 1
    return out


def decompress_lz4(input: List[UInt8], size: Int) raises -> List[UInt8]:
    """Expand OpenUSD's `TfFastCompression`, three.js's `decompressLZ4`.

    A first byte of zero is one LZ4 block. Any other is a count of chunks,
    then each chunk's compressed size as four bytes, then the chunks,
    each of which expands to 65536 bytes at most. A size byte past the
    end reads as zero, as JavaScript's `undefined | 0` is.

    Args:
        input: The compressed bytes.
        size: How many bytes they expand to.

    Returns:
        The bytes. Any that no block wrote are zero.

    Raises:
        Error: If the size is past `MAX_COUNT` times four, or a chunk runs
            past the end of the input.
    """
    if size < 0 or size > MAX_COUNT * 4 + 64:
        raise Error("USDC: an LZ4 size past this reader's limit")
    var output = List[UInt8](length=size, fill=0)
    if len(input) == 0:
        return output^
    var chunks = Int(input[0])
    if chunks == 0:
        _ = lz4_decompress_block(input, 1, len(input), output, 0, size)
        return output^
    var header = 1
    var sizes = List[Int]()
    for _ in range(chunks):
        var packed = 0
        for b in range(4):  # pragma: no branch
            if header + b < len(input):
                packed |= Int(input[header + b]) << (8 * b)
        sizes.append(packed)
        header += 4
    var at = header
    var out = 0
    for k in range(chunks):
        if sizes[k] > 0 and at + sizes[k] > len(input):
            raise Error("USDC: an LZ4 chunk runs past the end of its input")
        var produced = min(_CHUNK, size - out)
        _ = lz4_decompress_block(input, at, at + sizes[k], output, out, out + produced)
        at += sizes[k]
        out += produced
    return output^


def _int32(data: List[UInt8], at: Int, width: Int) -> Int:
    """Return a signed little-endian integer of one, two or four bytes.

    Args:
        data: The bytes.
        at: Where it starts.
        width: 1, 2 or 4.

    Returns:
        The integer.
    """
    var value = 0
    for b in range(width):  # pragma: no branch
        value |= Int(data[at + b]) << (8 * b)
    var top = 1 << (8 * width - 1)
    if value >= top:
        value -= top << 1
    return value


def _wrap32(value: Int) -> Int:
    """Return what an `Int32Array` stores for an integer.

    Args:
        value: The integer.

    Returns:
        It wrapped to 32 bits, signed.
    """
    var low = value & 0xFFFFFFFF
    return low - (1 << 32) if low >= (1 << 31) else low


def decode_integers32(data: List[UInt8], count: Int) -> List[Int]:
    """Sum OpenUSD's compressed integers, three.js's `decodeIntegers32`.

    The data is a common value, then two bits for each integer, then the
    differences that are not the common value, in one, two or four bytes.
    Each integer is the sum of the differences so far.

    Args:
        data: The expanded bytes: at least `count * 4 + (count * 2 + 7) /
            8 + 4` of them.
        count: How many integers.

    Returns:
        The integers, as an `Int32Array` holds them.
    """
    var common = _int32(data, 0, 4)
    var codes = 4
    var vints = 4 + ((count * 2 + 7) >> 3)
    var out = List[Int](capacity=count)
    var sum = 0
    var i = 0
    while i < count:
        var code_byte = Int(data[codes])
        codes += 1
        var j = 0
        while j < 4 and i < count:
            var code = (code_byte >> (j * 2)) & 3
            var delta = common
            if code == 1:
                delta = _int32(data, vints, 1)
                vints += 1
            elif code == 2:
                delta = _int32(data, vints, 2)
                vints += 2
            elif code == 3:
                delta = _int32(data, vints, 4)
                vints += 4
            sum += delta
            out.append(_wrap32(sum))
            j += 1
            i += 1
    return out^


def decompress_integers32(compressed: List[UInt8], count: Int) raises -> List[Int]:
    """Expand and sum OpenUSD's compressed integers, three.js's
    `decompressIntegers32`.

    Args:
        compressed: The LZ4 bytes.
        count: How many integers.

    Returns:
        The integers.

    Raises:
        Error: If the count is past `MAX_COUNT`, or the LZ4 bytes are
            refused.
    """
    if count < 0 or count > MAX_COUNT:
        raise Error("USDC: a count past this reader's limit")
    var size = count * 4 + ((count * 2 + 7) >> 3) + 4
    return decode_integers32(decompress_lz4(compressed, size), count)


def half_to_float(half: Int) -> Float64:
    """Return a half-precision float's value, three.js's `_halfToFloat`.

    Args:
        half: The sixteen bits.

    Returns:
        The number: a signed zero, a subnormal, an infinity, NaN, or a
        normal number.
    """
    var negative = (half & 0x8000) != 0
    var exponent = (half & 0x7C00) >> 10
    var fraction = half & 0x03FF
    var sign = Float64(-1) if negative else Float64(1)
    if exponent == 0:
        if fraction == 0:
            return sign * 0
        return sign * _two_to(-14) * (Float64(fraction) / 1024)
    if exponent == 31:
        if fraction != 0:
            return nan[DType.float64]()
        return sign * inf[DType.float64]()
    return sign * _two_to(exponent - 15) * (1 + Float64(fraction) / 1024)


def _two_to(power: Int) -> Float64:
    """Return two to a whole power, exactly.

    Args:
        power: The power, from -15 to 16.

    Returns:
        The number.
    """
    var out = Float64(1)
    for _ in range(abs(power)):
        out = out * 2 if power > 0 else out / 2
    return out


def _decode(data: List[UInt8], start: Int, end: Int) -> String:
    """Return bytes as a `TextDecoder` decodes them: UTF-8, with a
    replacement for each byte that is not.

    Args:
        data: The bytes.
        start: The first.
        end: One past the last.

    Returns:
        The text.
    """
    var part = List[UInt8](capacity=end - start)
    for k in range(start, end):
        part.append(data[k])
    return String(from_utf8_lossy=Span(part))


@fieldwise_init
struct _Rep(ImplicitlyCopyable):
    """A `ValueRep`: the value's 64 bits as two halves."""

    var lo: Int
    var hi: Int

    def type(self) -> CrateType:
        """Return the value's type: `CRATE_INVALID` for one outside the
        known ones, which three.js reads as it reads a type it does not
        support."""
        var type = CrateType((self.hi >> 16) & 0xFF)
        return type if type.is_valid() else CRATE_INVALID

    def is_array(self) -> Bool:
        """Return True for an array."""
        return (self.hi & 0x80000000) != 0

    def is_inlined(self) -> Bool:
        """Return True for a value held in the payload."""
        return (self.hi & 0x40000000) != 0

    def is_compressed(self) -> Bool:
        """Return True for a compressed array."""
        return (self.hi & 0x20000000) != 0

    def payload(self) -> Int:
        """Return the 48-bit payload."""
        return self.lo + ((self.hi & 0xFFFF) << 32)


@fieldwise_init
struct _Section(ImplicitlyCopyable):
    """Where a section of the table of contents is."""

    var start: Int
    var size: Int


@fieldwise_init
struct _CrateSpec(ImplicitlyCopyable):
    """A spec as the `SPECS` section holds it."""

    var path: Int
    var field_set: Int
    var spec_type: Int


struct _Crate(Movable):
    """three.js's `USDCParser` as it reads one file."""

    var bytes: List[UInt8]
    var at: Int
    var major: Int
    var minor: Int
    var patch: Int
    var toc: Int
    var names: List[String]
    var sections: List[_Section]
    var tokens: List[String]
    var strings: List[Int]
    var field_tokens: List[Int]
    var field_reps: List[_Rep]
    var field_sets: List[Int]
    # Each path by its index: three.js's array, which an index past its
    # length grows, and a negative one sets as a property.
    var paths: Dict[Int, String]
    var specs: List[_CrateSpec]
    var layer: UsdLayer

    def __init__(out self, var bytes: List[UInt8]):
        """Start reading a file.

        Args:
            bytes: The file.
        """
        self.bytes = bytes^
        self.at = 0
        self.major = 0
        self.minor = 0
        self.patch = 0
        self.toc = 0
        self.names = List[String]()
        self.sections = List[_Section]()
        self.tokens = List[String]()
        self.strings = List[Int]()
        self.field_tokens = List[Int]()
        self.field_reps = List[_Rep]()
        self.field_sets = List[Int]()
        self.paths = Dict[Int, String]()
        self.specs = List[_CrateSpec]()
        self.layer = UsdLayer()

    def need(self, count: Int) raises:
        """Refuse a read past the end, as a `DataView` throws.

        Args:
            count: How many bytes the read takes.

        Raises:
            Error: If they are not all in the file.
        """
        if self.at < 0 or count < 0 or self.at + count > len(self.bytes):
            raise Error("USDC: a read past the end of the file")

    def fits(self, count: Int, size: Int) raises:
        """Refuse a count of items that the rest of the file cannot hold.

        Args:
            count: How many items.
            size: Bytes an item.

        Raises:
            Error: If the count is negative or past `MAX_COUNT`, or the
                items would pass the end of the file.
        """
        if count < 0 or count > MAX_COUNT:
            raise Error("USDC: a count past this reader's limit")
        self.need(count * size)

    def unsigned(mut self, width: Int) raises -> Int:
        """Read an unsigned little-endian integer.

        Args:
            width: 1, 2, 4 or 8 bytes.

        Returns:
            The integer. Eight bytes past 2^63 read as negative.

        Raises:
            Error: If the bytes pass the end.
        """
        self.need(width)
        var value = 0
        for b in range(width):  # pragma: no branch
            value |= Int(self.bytes[self.at + b]) << (8 * b)
        self.at += width
        return value

    def signed(mut self, width: Int) raises -> Int:
        """Read a signed little-endian integer of 1, 2 or 4 bytes.

        Args:
            width: 1, 2 or 4 bytes.

        Returns:
            The integer.

        Raises:
            Error: If the bytes pass the end.
        """
        self.need(width)
        var value = _int32(self.bytes, self.at, width)
        self.at += width
        return value

    def u64_number(mut self) raises -> Float64:
        """Read three.js's `readUint64`: `hi * 2^32 + lo` as a double.

        Returns:
            The number.

        Raises:
            Error: If the bytes pass the end.
        """
        var lo = self.unsigned(4)
        var hi = self.unsigned(4)
        return Float64(hi) * 4294967296.0 + Float64(lo)

    def i64_number(mut self) raises -> Float64:
        """Read three.js's `readInt64`: a signed high half.

        Returns:
            The number.

        Raises:
            Error: If the bytes pass the end.
        """
        var lo = self.unsigned(4)
        var hi = self.signed(4)
        return Float64(hi) * 4294967296.0 + Float64(lo)

    def f32(mut self) raises -> Float64:
        """Read a float.

        Returns:
            The float, as a double.

        Raises:
            Error: If the bytes pass the end.
        """
        var bits = UInt32(self.unsigned(4))
        return Float64(bitcast[DType.float32](bits))

    def f64(mut self) raises -> Float64:
        """Read a double.

        Returns:
            The double.

        Raises:
            Error: If the bytes pass the end.
        """
        var bits = UInt64(self.unsigned(8))
        return bitcast[DType.float64](bits)

    def half(mut self) raises -> Float64:
        """Read a half.

        Returns:
            Its value.

        Raises:
            Error: If the bytes pass the end.
        """
        return half_to_float(self.unsigned(2))

    def take(mut self, count: Int) raises -> List[UInt8]:
        """Read bytes, three.js's `readBytes`.

        Args:
            count: How many.

        Returns:
            The bytes.

        Raises:
            Error: If they pass the end.
        """
        self.need(count)
        var out = List[UInt8](capacity=count)
        for k in range(count):
            out.append(self.bytes[self.at + k])
        self.at += count
        return out^

    def text(mut self, count: Int) raises -> String:
        """Read three.js's `readString`: bytes up to the first zero.

        Args:
            count: How many bytes the field takes.

        Returns:
            The text, decoded as a `TextDecoder` decodes it.

        Raises:
            Error: If the bytes pass the end.
        """
        var field = self.take(count)
        var end = 0
        while end < count and field[end] != 0:
            end += 1
        return _decode(field, 0, end)

    def section(self, name: String) -> Int:
        """Return where a section is in `sections`.

        Args:
            name: The section.

        Returns:
            The place of the last section of that name, or -1.
        """
        var found = -1
        for k in range(len(self.names)):
            if self.names[k] == name:
                found = k
        return found

    def required(self, name: String) raises -> _Section:
        """Return a section that must be there.

        Args:
            name: The section.

        Returns:
            Where it is.

        Raises:
            Error: If the file has no such section.
        """
        var at = self.section(name)
        if at < 0:
            raise Error("USDC: the file has no " + name + " section")
        return self.sections[at]

    def compressed(self) -> Bool:
        """Return True from version 0.4.0, whose sections are compressed."""
        return not (self.major == 0 and self.minor < 4)

    def count(mut self) raises -> Int:
        """Read a count: a `uint64` held to `MAX_COUNT`.

        Returns:
            The count.

        Raises:
            Error: If it passes the end or `MAX_COUNT`.
        """
        var value = self.unsigned(8)
        if value < 0 or value > MAX_COUNT:
            raise Error("USDC: a count past this reader's limit")
        return value

    def integers(mut self, count: Int) raises -> List[Int]:
        """Read a compressed size and that many bytes of compressed
        integers.

        Args:
            count: How many integers.

        Returns:
            The integers.

        Raises:
            Error: If the bytes pass the end.
        """
        var size = self.unsigned(8)
        return decompress_integers32(self.take(size), count)

    def bootstrap(mut self) raises:
        """Read the magic, the version and where the table of contents is,
        three.js's `_readBootstrap`.

        Raises:
            Error: If the file does not start with `PXR-USDC`.
        """
        self.at = 0
        if self.text(8) != "PXR-USDC":
            raise Error("USDC: not a valid USDC file")
        self.major = self.unsigned(1)
        self.minor = self.unsigned(1)
        self.patch = self.unsigned(1)
        _ = self.take(5)
        self.toc = self.unsigned(8)

    def table(mut self) raises:
        """Read the table of contents, three.js's `_readTOC`.

        Raises:
            Error: If it passes the end.
        """
        self.at = self.toc
        var count = self.count()
        for _ in range(count):
            var name = self.text(16)
            var start = self.unsigned(8)
            var size = self.unsigned(8)
            self.names.append(name)
            self.sections.append(_Section(start, size))

    def split_tokens(mut self, data: List[UInt8], count: Int):
        """Cut the tokens out of their bytes, each ended by a zero.

        Args:
            data: The bytes.
            count: How many tokens.
        """
        var start = 0
        for _ in range(count):
            var end = start
            while end < len(data) and data[end] != 0:
                end += 1
            var first = min(start, len(data))
            self.tokens.append(_decode(data, first, max(first, end)))
            start = end + 1

    def read_tokens(mut self) raises:
        """Read `TOKENS`, three.js's `_readTokens`.

        Raises:
            Error: If the section is missing or passes the end.
        """
        self.at = self.required("TOKENS").start
        var count = self.count()
        if not self.compressed():
            var size = self.unsigned(8)
            var data = self.take(size)
            self.split_tokens(data, count)
            return
        var size = self.unsigned(8)
        var packed = self.unsigned(8)
        var data = decompress_lz4(self.take(packed), size)
        self.split_tokens(data, count)

    def read_strings(mut self) raises:
        """Read `STRINGS`, three.js's `_readStrings`: indices into the
        tokens. A file with no such section has none.

        Raises:
            Error: If it passes the end.
        """
        var at = self.section("STRINGS")
        if at < 0:
            return
        self.at = self.sections[at].start
        var count = self.count()
        self.fits(count, 4)
        for _ in range(count):
            self.strings.append(self.unsigned(4))

    def read_fields(mut self) raises:
        """Read `FIELDS`, three.js's `_readFields`: each field's token and
        `ValueRep`.

        Raises:
            Error: If the section is missing or passes the end.
        """
        var section = self.required("FIELDS")
        self.at = section.start
        if not self.compressed():
            var count = section.size // 12
            self.fits(count, 12)
            for _ in range(count):
                self.field_tokens.append(self.unsigned(4))
                var lo = self.unsigned(4)
                var hi = self.unsigned(4)
                self.field_reps.append(_Rep(lo, hi))
            return
        var count = self.count()
        self.field_tokens = self.integers(count)
        var size = self.unsigned(8)
        var reps = decompress_lz4(self.take(size), count * 8)
        for k in range(count):
            var lo = 0
            var hi = 0
            for b in range(4):  # pragma: no branch
                lo |= Int(reps[k * 8 + b]) << (8 * b)
                hi |= Int(reps[k * 8 + 4 + b]) << (8 * b)
            self.field_reps.append(_Rep(lo, hi))

    def read_field_sets(mut self) raises:
        """Read `FIELDSETS`, three.js's `_readFieldSets`.

        Raises:
            Error: If the section is missing or passes the end.
        """
        var section = self.required("FIELDSETS")
        self.at = section.start
        if not self.compressed():
            var count = section.size // 4
            self.fits(count, 4)
            for _ in range(count):
                self.field_sets.append(self.unsigned(4))
            return
        var count = self.count()
        self.field_sets = self.integers(count)

    def token(self, index: Int) -> String:
        """Return `this.tokens[ index ] || ''`.

        Args:
            index: The token.

        Returns:
            It, or the empty string past the list.
        """
        if index < 0 or index >= len(self.tokens):
            return ""
        return self.tokens[index]

    def path(self, index: Int) -> String:
        """Return `this.paths[ index ]`, empty when it is not set.

        Args:
            index: The path.

        Returns:
            It, or the empty string when it is not set.
        """
        return self.paths.get(index).or_else("")

    def set_path(mut self, index: Int, path: String):
        """Set a path, three.js's `this.paths[ index ] = path`.

        Args:
            index: The path's index.
            path: The path.
        """
        self.paths[index] = path

    def read_paths(mut self) raises:
        """Read `PATHS`, three.js's `_readPaths`.

        Raises:
            Error: If the section is missing or passes the end.
        """
        self.at = self.required("PATHS").start
        var count = self.count()
        if not self.compressed():
            self.walk_paths("", 0)
            return
        _ = self.unsigned(8)
        var indices = self.integers(count)
        var elements = self.integers(count)
        var jumps = self.integers(count)
        var budget = count * 16 + 16
        self.build_paths(indices, elements, jumps, 0, "", budget)

    def walk_paths(mut self, parent: String, depth: Int) raises:
        """Read the path tree of a file before 0.4.0, three.js's
        `_readPathsRecursive`.

        Args:
            parent: The parent's path, empty for the root.
            depth: How deep this is. Past 1000 the walk stops, as in
                three.js.

        Raises:
            Error: If it passes the end.
        """
        if depth > 1000:
            return
        var index = self.unsigned(4)
        var element = self.unsigned(4)
        var bits = self.unsigned(1)
        var has_child = (bits & 1) != 0
        var has_sibling = (bits & 2) != 0
        var property = (bits & 4) != 0
        var path = _child_path(parent, self.token(element), property)
        self.set_path(index, path)
        if has_child and has_sibling:
            var sibling = self.unsigned(8)
            self.walk_paths(path, depth + 1)
            self.at = sibling
            self.walk_paths(parent, depth + 1)
        elif has_child:
            self.walk_paths(path, depth + 1)
        elif has_sibling:
            self.walk_paths(parent, depth + 1)

    def build_paths(
        mut self,
        indices: List[Int],
        elements: List[Int],
        jumps: List[Int],
        start: Int,
        parent_path: String,
        mut budget: Int,
    ) raises:
        """Build the paths of a compressed tree, three.js's
        `_buildPathsFromCompressed`.

        A jump of -1 means the next entry is a child, 0 a sibling, -2
        neither, and one above zero both, with the sibling that far on.

        Args:
            indices: Each entry's path index.
            elements: Each entry's token, negative for a property.
            jumps: Each entry's jump.
            start: The entry to start at.
            parent_path: The parent's path, empty for the root.
            budget: Entries left to visit. The walk refuses a tree that
                visits more, where three.js would not end.

        Raises:
            Error: If the budget runs out.
        """
        var parent = parent_path
        var at = start
        while at < len(indices):
            budget -= 1
            if budget < 0:
                raise Error("USDC: a path tree that does not end")
            var this = at
            at += 1
            var path: String
            if parent == "":
                path = "/"
                parent = path
            else:
                var element = elements[this]
                path = _child_path(parent, self.token(abs(element)), element < 0)
            self.set_path(indices[this], path)
            var jump = jumps[this]
            var has_child = jump > 0 or jump == -1
            var has_sibling = jump >= 0
            if has_child:
                if has_sibling:
                    self.build_paths(indices, elements, jumps, this + jump, parent, budget)
                parent = path
            elif not has_sibling:
                break

    def read_specs(mut self) raises:
        """Read `SPECS`, three.js's `_readSpecs`.

        Raises:
            Error: If the section is missing or passes the end.
        """
        var section = self.required("SPECS")
        self.at = section.start
        if not self.compressed():
            # Version 0.0.1 pads each spec to sixteen bytes.
            var size = 16 if self.minor == 0 and self.patch == 1 else 12
            var count = section.size // size
            self.fits(count, size)
            for _ in range(count):
                var path = self.unsigned(4)
                var field_set = self.unsigned(4)
                var spec_type = self.unsigned(4)
                if size == 16:
                    _ = self.unsigned(4)
                self.specs.append(_CrateSpec(path, field_set, spec_type))
            return
        var count = self.count()
        var paths = self.integers(count)
        var field_sets = self.integers(count)
        var types = self.integers(count)
        for k in range(count):
            self.specs.append(_CrateSpec(paths[k], field_sets[k], types[k]))

    def value(mut self, rep: _Rep, depth: Int) raises -> Int:
        """Read a value, three.js's `_readValue`.

        Args:
            rep: Its `ValueRep`.
            depth: How deep in time samples this is.

        Returns:
            Its place in the layer.

        Raises:
            Error: For a payload past the end, and anything a read
                refuses.
        """
        var type = rep.type()
        if type == CRATE_TIME_SAMPLES:
            return self.time_samples(rep, depth)
        if rep.is_inlined():
            return self.layer.add(self.inlined(rep))
        var offset = rep.payload()
        if offset == 0 and rep.is_array():
            return self.layer.add(UsdValue(USD_NUMBERS))
        if offset >= len(self.bytes):
            raise Error("USDC: a payload offset past the end of the file")
        var saved = self.at
        self.at = offset
        var out: Int
        if rep.is_array():
            out = self.layer.add(self.array(rep))
        else:
            out = self.scalar(type)
        self.at = saved
        return out

    def inlined(self, rep: _Rep) -> UsdValue:
        """Read a value held in its payload, three.js's
        `_readInlinedValue`.

        Args:
            rep: Its `ValueRep`.

        Returns:
            The value.
        """
        var type = rep.type()
        var payload = rep.lo
        if type == CRATE_BOOL:
            return usd_boolean(payload != 0)
        if type == CRATE_UCHAR:
            return usd_number(Float64(payload & 0xFF))
        if type == CRATE_FLOAT or type == CRATE_DOUBLE:
            # A double inlined is held as the bits of a float.
            return usd_number(Float64(bitcast[DType.float32](UInt32(payload))))
        if type == CRATE_TOKEN or type == CRATE_ASSET_PATH:
            return usd_string(self.token(payload))
        if type == CRATE_STRING:
            var string = -1
            if payload < len(self.strings):
                string = self.strings[payload]
            return usd_string(self.token(string))
        if type == CRATE_VEC2H:
            return usd_numbers(
                [half_to_float(payload & 0xFFFF), half_to_float(payload >> 16)]
            )
        var bytes = List[Float64]()
        for b in range(4):  # pragma: no branch
            bytes.append(Float64(_int32_of_byte((payload >> (8 * b)) & 0xFF)))
        if type == CRATE_VEC2F or type == CRATE_VEC2I:
            return usd_numbers([bytes[0], bytes[1]])
        if type == CRATE_VEC3F or type == CRATE_VEC3I:
            return usd_numbers([bytes[0], bytes[1], bytes[2]])
        if type == CRATE_VEC4F or type == CRATE_VEC4I:
            return usd_numbers(bytes^)
        if type == CRATE_MATRIX2D:
            return usd_numbers([bytes[0], 0, 0, bytes[1]])
        if type == CRATE_MATRIX3D:
            return usd_numbers(
                [bytes[0], 0, 0, 0, bytes[1], 0, 0, 0, bytes[2]]
            )
        if type == CRATE_MATRIX4D:
            var m = List[Float64](length=16, fill=0)
            for k in range(4):  # pragma: no branch
                m[k * 5] = bytes[k]
            return usd_numbers(m^)
        # An int, an unsigned int, a specifier, a permission, a
        # variability, and any other type three.js does not know inlined.
        return usd_number(Float64(payload))

    def time_samples(mut self, rep: _Rep, depth: Int) raises -> Int:
        """Read time samples, three.js's `_readTimeSamples`.

        The payload is where a relative offset to the times' `ValueRep`
        is. After that `ValueRep` is a relative offset to a count and the
        values' `ValueRep`s.

        Args:
            rep: Its `ValueRep`.
            depth: How deep in time samples this is.

        Returns:
            Its place in the layer.

        Raises:
            Error: If the times are not numbers, the samples nest past 64
                deep, or a read refuses.
        """
        if depth > _MAX_DEPTH:
            raise Error("USDC: time samples nested too deep")
        var saved = self.at
        var times_start = rep.payload()
        self.at = times_start
        var relative = Int(self.i64_number())
        self.at = times_start + relative
        var lo = self.unsigned(4)
        var hi = self.unsigned(4)
        var times = self.value(_Rep(lo, hi), depth + 1)
        self.at = times_start + relative + 8
        var values_start = self.at
        var values_relative = Int(self.i64_number())
        self.at = values_start + values_relative
        var count = self.count()
        self.fits(count, 8)
        var reps = List[_Rep]()
        for _ in range(count):
            var value_lo = self.unsigned(4)
            var value_hi = self.unsigned(4)
            reps.append(_Rep(value_lo, value_hi))
        var out = UsdValue(USD_SAMPLES)
        for k in range(count):
            out.items.append(self.value(reps[k], depth + 1))
        self.at = saved
        var kind = self.layer.kind(times)
        if kind == USD_NUMBERS:
            out.numbers = self.layer.values[times].numbers.copy()
        elif self.layer.is_number(times):
            out.numbers = [self.layer.number(times)]
        else:
            raise Error("USDC: time samples whose times are not numbers")
        return self.layer.add(out^)

    def path_list(mut self) raises -> List[String]:
        """Read a list of paths: a count and a path index for each.

        Returns:
            The paths.

        Raises:
            Error: If it passes the end.
        """
        var count = self.count()
        self.fits(count, 4)
        var out = List[String]()
        for _ in range(count):
            out.append(self.path(self.unsigned(4)))
        return out^

    def scalar(mut self, type: CrateType) raises -> Int:
        """Read a value that is not an array, three.js's
        `_readScalarValue`.

        Args:
            type: Its type.

        Returns:
            Its place in the layer.

        Raises:
            Error: If a read refuses.
        """
        var value: UsdValue
        if type == CRATE_BOOL:
            value = usd_boolean(self.unsigned(1) != 0)
        elif type == CRATE_UCHAR:
            value = usd_number(Float64(self.unsigned(1)))
        elif type == CRATE_INT:
            value = usd_number(Float64(self.signed(4)))
        elif type == CRATE_UINT:
            value = usd_number(Float64(self.unsigned(4)))
        elif type == CRATE_INT64:
            value = usd_number(self.i64_number())
        elif type == CRATE_UINT64:
            value = usd_number(self.u64_number())
        elif type == CRATE_HALF:
            value = usd_number(self.half())
        elif type == CRATE_FLOAT:
            value = usd_number(self.f32())
        elif type == CRATE_DOUBLE:
            value = usd_number(self.f64())
        elif (
            type == CRATE_STRING
            or type == CRATE_TOKEN
            or type == CRATE_ASSET_PATH
        ):
            value = usd_string(self.token(self.unsigned(4)))
        elif type == CRATE_VEC2F or type == CRATE_VEC3F or type == CRATE_VEC4F:
            value = self.floats(_width(type), 4)
        elif type == CRATE_QUATF:
            value = self.floats(4, 4)
        elif type == CRATE_VEC2D or type == CRATE_VEC3D or type == CRATE_VEC4D:
            value = self.floats(_width(type), 8)
        elif type == CRATE_QUATD:
            value = self.floats(4, 8)
        elif type == CRATE_MATRIX4D:
            value = self.floats(16, 8)
        elif type == CRATE_VEC2I or type == CRATE_VEC3I:
            var numbers = List[Float64]()
            for _ in range(_width(type)):
                numbers.append(Float64(self.signed(4)))
            value = usd_numbers(numbers^)
        elif type == CRATE_TOKEN_VECTOR:
            var count = self.count()
            self.fits(count, 4)
            var strings = List[String]()
            for _ in range(count):
                strings.append(self.token(self.unsigned(4)))
            value = usd_strings(strings^)
        elif type == CRATE_PATH_VECTOR:
            value = usd_strings(self.path_list())
        elif type == CRATE_DOUBLE_VECTOR:
            var count = self.count()
            value = self.floats(count, 8)
        elif type == CRATE_DICTIONARY:
            value = self.dictionary()
        elif type == CRATE_PATH_LIST_OP:
            value = self.path_list_op()
        elif type == CRATE_VARIANT_SELECTION_MAP:
            value = self.variant_selections()
        else:
            # `Invalid`, the other list operations, and every type three.js
            # does not read.
            value = UsdValue(USD_NULL)
        return self.layer.add(value^)

    def floats(mut self, count: Int, size: Int) raises -> UsdValue:
        """Read floats or doubles.

        Args:
            count: How many.
            size: 4 for floats, 8 for doubles.

        Returns:
            An array of numbers.

        Raises:
            Error: If they pass the end.
        """
        self.fits(count, size)
        var numbers = List[Float64](capacity=count)
        for _ in range(count):
            numbers.append(self.f32() if size == 4 else self.f64())
        return usd_numbers(numbers^)

    def dictionary(mut self) raises -> UsdValue:
        """Read a dictionary as three.js's reader does: it reads a key,
        an offset and eight bytes for each element and keeps none.

        Returns:
            An empty object.

        Raises:
            Error: If the reads pass the end.
        """
        var count = self.count()
        self.fits(count, 20)
        self.at += count * 20
        return UsdValue(USD_OBJECT)

    def path_list_op(mut self) raises -> UsdValue:
        """Read a list operation of paths, three.js's `PathListOp` case.

        A byte of flags says which lists follow: explicit, add, prepend,
        append, delete and reorder, in that order.

        Returns:
            The first list of the prepended, explicit, appended and added
            ones that is not empty, or `null`.

        Raises:
            Error: If it passes the end.
        """
        var flags = self.unsigned(1)
        var lists = List[List[String]]()
        # Explicit, add, prepend and append, in the file's order.
        var bits: List[Int] = [0x02, 0x04, 0x20, 0x40]
        for bit in bits:  # pragma: no branch
            if (flags & bit) != 0:
                lists.append(self.path_list())
            else:
                lists.append(List[String]())
        if (flags & 0x08) != 0:
            _ = self.path_list()
        if (flags & 0x10) != 0:
            _ = self.path_list()
        # three.js's preference: prepend, explicit, append, add.
        var order: List[Int] = [2, 0, 3, 1]
        for k in order:  # pragma: no branch
            if len(lists[k]) > 0:
                return usd_strings(lists[k].copy())
        return UsdValue(USD_NULL)

    def variant_selections(mut self) raises -> UsdValue:
        """Read a variant selection map: a count, then two string indices
        for each element.

        Returns:
            An object of each variant set's selection. A key or a value
            that is empty is left out.

        Raises:
            Error: If it passes the end.
        """
        var count = self.count()
        self.fits(count, 8)
        var out = UsdValue(USD_OBJECT)
        for _ in range(count):
            var key = self.string(self.unsigned(4))
            var chosen = self.string(self.unsigned(4))
            if key != "" and chosen != "":
                var at = -1
                for k in range(len(out.strings)):
                    if out.strings[k] == key:
                        at = k
                var id = self.layer.add(usd_string(chosen))
                if at < 0:
                    out.strings.append(key)
                    out.items.append(id)
                else:
                    out.items[at] = id
        return out^

    def string(self, index: Int) -> String:
        """Return `this.tokens[ this.strings[ index ] ]`.

        Args:
            index: The string.

        Returns:
            Its token, or the empty string past either list.
        """
        if index < 0 or index >= len(self.strings):
            return ""
        return self.token(self.strings[index])

    def array(mut self, rep: _Rep) raises -> UsdValue:
        """Read an array, three.js's `_readArrayValue`.

        Args:
            rep: Its `ValueRep`.

        Returns:
            The array. One of a type three.js does not read is empty.

        Raises:
            Error: If its size is past 2^31 - 1 or the file, or a read
                refuses.
        """
        var type = rep.type()
        var size: Int
        if self.major == 0 and self.minor < 7:
            size = self.unsigned(4)
        else:
            size = self.unsigned(8)
        if size < 0 or size > 0x7FFFFFFF:
            raise Error("USDC: an array size past 2^31 - 1")
        if size == 0:
            return UsdValue(USD_NUMBERS)
        if rep.is_compressed():
            return self.compressed_array(type, size)
        if type == CRATE_INT or type == CRATE_UINT:
            self.fits(size, 4)
            var numbers = List[Float64](capacity=size)
            for _ in range(size):
                if type == CRATE_INT:
                    numbers.append(Float64(self.signed(4)))
                else:
                    numbers.append(Float64(self.unsigned(4)))
            return usd_numbers(numbers^)
        if type == CRATE_FLOAT:
            return self.floats(size, 4)
        if type == CRATE_DOUBLE:
            return self.floats(size, 8)
        if type == CRATE_VEC2F or type == CRATE_VEC3F or type == CRATE_VEC4F:
            return self.floats(size * _width(type), 4)
        if type == CRATE_QUATF:
            return self.floats(size * 4, 4)
        if type == CRATE_MATRIX4D:
            return self.floats(size * 16, 8)
        if type == CRATE_HALF or type == CRATE_VEC3H or type == CRATE_QUATH:
            var count = size * (_width(type) if type == CRATE_VEC3H else 1)
            if type == CRATE_QUATH:
                count = size * 4
            self.fits(count, 2)
            var numbers = List[Float64](capacity=count)
            for _ in range(count):
                numbers.append(self.half())
            return usd_numbers(numbers^)
        if type == CRATE_TOKEN:
            self.fits(size, 4)
            var strings = List[String](capacity=size)
            for _ in range(size):
                strings.append(self.token(self.unsigned(4)))
            return usd_strings(strings^)
        return UsdValue(USD_NUMBERS)

    def compressed_array(mut self, type: CrateType, size: Int) raises -> UsdValue:
        """Read a compressed array, three.js's `_readCompressedArray`.

        Args:
            type: Its type.
            size: How many elements.

        Returns:
            The array. One of a type three.js does not expand is empty.

        Raises:
            Error: If a read or the expansion refuses.
        """
        if type == CRATE_INT or type == CRATE_UINT:
            var ints = self.integers(size)
            var numbers = List[Float64](capacity=size)
            for value in ints:
                numbers.append(Float64(value))
            return usd_numbers(numbers^)
        if type != CRATE_FLOAT:
            return UsdValue(USD_NUMBERS)
        var code = self.signed(1)
        var numbers = List[Float64](capacity=size)
        if code == _FLOAT_AS_INTS:
            for value in self.integers(size):
                numbers.append(Float64(Float32(Float64(value))))
        elif code == _FLOAT_TABLE:
            var entries = self.unsigned(4)
            self.fits(entries, 4)
            var table = List[Float64]()
            for _ in range(entries):
                table.append(self.f32())
            for index in self.integers(size):
                if index >= 0 and index < entries:
                    numbers.append(table[index])
                else:
                    numbers.append(nan[DType.float64]())
        else:
            numbers = List[Float64](length=size, fill=0)
        return usd_numbers(numbers^)

    def fields_of(mut self, spec: _CrateSpec) raises -> UsdSpec:
        """Read a spec's fields, three.js's `_getFieldsForSpec`.

        The fields run from the spec's field set to a terminator, ten
        thousand at most. A field set or a field past its list is
        skipped, and a token past its list names the field `undefined`,
        as in three.js.

        Args:
            spec: The spec.

        Returns:
            The spec with its fields.

        Raises:
            Error: If its spec type is not valid, or a value refuses.
        """
        var spec_type = SpecType(spec.spec_type)
        if not spec_type.is_valid():
            raise Error("USDC: a spec of no known type: " + String(spec.spec_type))
        var out = UsdSpec(spec_type)
        var at = spec.field_set
        var steps = 0
        while at < len(self.field_sets) and steps < 10000:
            if at >= 0:
                var field = self.field_sets[at]
                if field == _TERMINATOR or field == -1:
                    break
                if field >= 0 and field < len(self.field_reps):
                    var token = self.field_tokens[field]
                    var name = String("undefined")
                    if token >= 0 and token < len(self.tokens):
                        name = self.tokens[token]
                    var rep = self.field_reps[field]
                    out.set(name, self.value(rep, 0))
            at += 1
            steps += 1
        return out^


def _int32_of_byte(byte: Int) -> Int:
    """Return a byte read as a signed eight-bit integer.

    Args:
        byte: The byte.

    Returns:
        It, from -128 to 127.
    """
    return byte - 256 if byte >= 128 else byte


def _width(type: CrateType) -> Int:
    """Return how many numbers a vector type holds.

    Args:
        type: A vector type.

    Returns:
        2, 3 or 4.
    """
    if type == CRATE_VEC2F or type == CRATE_VEC2D or type == CRATE_VEC2I:
        return 2
    if (
        type == CRATE_VEC3F
        or type == CRATE_VEC3D
        or type == CRATE_VEC3I
        or type == CRATE_VEC3H
    ):
        return 3
    return 4


def _child_path(parent: String, element: String, property: Bool) -> String:
    """Return a path under its parent, as three.js's path readers build it.

    Args:
        parent: The parent's path, empty for the root.
        element: The last part.
        property: Whether it is a property, after a `.`.

    Returns:
        `/` for the root, `parent.element` for a property, and
        `parent/element` for anything else.
    """
    if parent == "":
        return "/"
    if property:
        return parent + "." + element
    if parent == "/":
        return "/" + element
    return parent + "/" + element


def parse_usdc(var bytes: List[UInt8]) raises -> UsdLayer:
    """Read a USDC crate into a layer, three.js's `USDCParser.parseData`.

    Args:
        bytes: The file.

    Returns:
        Each path's spec, in the order of the `SPECS` section. A spec
        whose path is not set is left out, as in three.js.

    Raises:
        Error: For anything the module docstring lists.
    """
    var crate = _Crate(bytes^)
    crate.bootstrap()
    crate.table()
    crate.read_tokens()
    crate.read_strings()
    crate.read_fields()
    crate.read_field_sets()
    crate.read_paths()
    crate.read_specs()
    for k in range(len(crate.specs)):
        var spec = crate.specs[k]
        var path = crate.path(spec.path)
        if path == "":
            continue
        var fields = crate.fields_of(spec)
        _ = crate.layer.put(path, fields^)
    var layer = UsdLayer()
    swap(layer, crate.layer)
    return layer^

