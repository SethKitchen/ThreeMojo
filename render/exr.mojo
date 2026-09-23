# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""An OpenEXR reader, three.js's `EXRLoader`.

An EXR file is a magic number, a version, a header of named attributes, a
table of where each block of scanlines starts, and the blocks. The header
says which channels there are, each half or float, how the blocks are
compressed, and which rectangle the pixels cover. Each block holds a few
scanlines, and each scanline holds every pixel of one channel, then every
pixel of the next, in the header's channel order.

**What is read.** Single-part scanline files, version two, with channels
of half or float samples at full resolution, compressed with none, RLE,
ZIPS, ZIP or PIZ. An image with `R`, `G` and `B` becomes RGBA, with `A` as
its alpha or one where it has none; an image with `Y` alone becomes gray,
alpha one. Any other channel is read past. This is three.js's default
`RGBAFormat` output. three.js's default `type` is `HalfFloatType`; the
reader returns floats, which hold every half exactly and every float as it
is, as three.js's `FloatType` output does.

**What is not.** Tiled, deep and multi-part files; PXR24, B44, B44A, DWAA
and DWAB compression; luminance-chroma images with `RY` and `BY`, whose
chroma is stored at a quarter of the resolution; subsampled channels; and
`UINT` color channels. three.js reads the first four groups; this reader
refuses each by name. three.js does not read `UINT` color either.

**Where it differs from three.js, it refuses rather than guesses.** three.js
reads every color channel with the pixel type of the last one it met, so a
file of half red and float alpha misreads one of them; this reader reads
each channel as its own type. three.js ignores a channel's sampling and
misreads a subsampled one; this reader refuses it. three.js reads past the
end of a block, a Huffman table or the file as whatever the array holds
there; this reader refuses each. A block that names a line outside the
image is refused, and so is a block that does not expand to its lines.

The rows come out from the top, the first line of the data window first,
as every other reader here returns them. three.js flips them and marks the
texture `flipY = false`, which samples the same way.
"""

from render.float_image import FloatImage
from render.inflate import zlib_inflate
from render.png import MAX_PIXELS
from render.texture import float_from_bytes
from std.memory import bitcast

# The first four bytes of every OpenEXR file, as a little-endian integer.
comptime MAGIC = 20000630
# The only file version there is.
comptime VERSION = 2
# The version field's flag bits for the layouts this reader does not read.
comptime SINGLE_TILE = 0x02
comptime DEEP_DATA = 0x08
comptime MULTI_PART = 0x10

# PIZ's constants, named as OpenEXR and three.js name them.
comptime USHORT_RANGE = 1 << 16
comptime BITMAP_SIZE = USHORT_RANGE >> 3
comptime HUF_ENCBITS = 16
comptime HUF_DECBITS = 14
comptime HUF_ENCSIZE = (1 << HUF_ENCBITS) + 1
comptime HUF_DECSIZE = 1 << HUF_DECBITS
comptime HUF_DECMASK = HUF_DECSIZE - 1
comptime SHORT_ZEROCODE_RUN = 59
comptime LONG_ZEROCODE_RUN = 63
comptime SHORTEST_LONG_RUN = 2 + LONG_ZEROCODE_RUN - SHORT_ZEROCODE_RUN
# The longest code length a packed table can spell: six bits, less the
# five values that mean a run of zeros.
comptime MAX_CODE_LENGTH = 58
# How many bits of the Huffman reader's accumulator are kept. Only the
# bits not yet consumed matter, and a code is never longer than
# `MAX_CODE_LENGTH`, so this is room enough and no shift can overflow.
comptime ACCUMULATOR_MASK = (1 << 62) - 1
# The two wavelet decoders: 14-bit when every value fits, 16-bit else.
comptime A_OFFSET = 1 << 15
comptime MOD_MASK = (1 << 16) - 1


@fieldwise_init
struct ExrCompression(Equatable, ImplicitlyCopyable, Writable):
    """How an EXR file's blocks are compressed, as a type: the header's
    `compression` byte.

    See `core.object3d.NodeId` for why it is wrapped. The type does not
    stop `ExrCompression(9)`, so `lines_per_block` asks `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is one of the five this reader reads.

        Returns:
            Whether it is none, RLE, ZIPS, ZIP or PIZ. PXR24, B44, B44A,
            DWAA and DWAB are compressions OpenEXR defines and this
            reader does not read.
        """
        return self.value >= NO_COMPRESSION.value and (
            self.value <= PIZ_COMPRESSION.value
        )


# Each scanline as it stands, one to a block.
comptime NO_COMPRESSION = ExrCompression(0)
# Run-length encoded bytes, one scanline to a block.
comptime RLE_COMPRESSION = ExrCompression(1)
# zlib, one scanline to a block.
comptime ZIPS_COMPRESSION = ExrCompression(2)
# zlib, sixteen scanlines to a block.
comptime ZIP_COMPRESSION = ExrCompression(3)
# A wavelet and Huffman coding, thirty-two scanlines to a block.
comptime PIZ_COMPRESSION = ExrCompression(4)


def lines_per_block(compression: ExrCompression) raises -> Int:
    """Return how many scanlines one block of a compression holds.

    Args:
        compression: One of the five this reader reads.

    Returns:
        One for none, RLE and ZIPS; sixteen for ZIP; thirty-two for PIZ.

    Raises:
        Error: If the compression is not one this reader reads.
    """
    if not compression.is_valid():
        raise Error(
            "EXR: only none, RLE, ZIPS, ZIP and PIZ compression are read;"
            " PXR24, B44 and DWA are not ported"
        )
    if compression == ZIP_COMPRESSION:
        return 16
    if compression == PIZ_COMPRESSION:
        return 32
    return 1


@fieldwise_init
struct ExrPixelType(Equatable, ImplicitlyCopyable, Writable):
    """What one sample of a channel is, as a type: a channel's
    `pixel_type`.

    The type does not stop `ExrPixelType(9)`, so `sample_bytes` asks
    `is_valid`.
    """

    var value: Int

    def is_valid(self) -> Bool:
        """Return True if this is `UINT_SAMPLES`, `HALF_SAMPLES` or
        `FLOAT_SAMPLES`."""
        return (
            self == UINT_SAMPLES
            or self == HALF_SAMPLES
            or self == FLOAT_SAMPLES
        )


# An unsigned 32-bit integer: an id, not light. Read past, never shown.
comptime UINT_SAMPLES = ExrPixelType(0)
# An IEEE 754 half, two bytes.
comptime HALF_SAMPLES = ExrPixelType(1)
# An IEEE 754 single, four bytes.
comptime FLOAT_SAMPLES = ExrPixelType(2)


def sample_bytes(kind: ExrPixelType) raises -> Int:
    """Return how many bytes one sample of a pixel type takes.

    Args:
        kind: The channel's pixel type.

    Returns:
        Two for a half, four for a float or an unsigned integer.

    Raises:
        Error: If the pixel type is none of the three.
    """
    if not kind.is_valid():
        raise Error("EXR: a channel's pixel type must be UINT, HALF or FLOAT")
    if kind == HALF_SAMPLES:
        return 2
    return 4


def half_to_float(bits: UInt16) -> Float32:
    """Return the float an IEEE 754 half's bits spell, exactly.

    three.js's `decodeFloat16`: a subnormal is its fraction times two to
    the minus twenty-four, a normal number is rebuilt with its exponent
    rebiased, and an exponent of all ones is an infinity or a NaN.

    Args:
        bits: The half's sixteen bits.

    Returns:
        The same number as a float.
    """
    var sign = UInt32(bits >> 15) << 31
    var exponent = Int((bits >> 10) & 0x1F)
    var fraction = UInt32(bits & 0x3FF)
    if exponent == 0:
        var tiny = Float32(Int(fraction)) * Float32(5.9604644775390625e-8)
        if sign != 0:
            return -tiny
        return tiny
    if exponent == 0x1F:
        return bitcast[DType.float32](sign | 0x7F800000 | (fraction << 13))
    return bitcast[DType.float32](
        sign | (UInt32(exponent - 15 + 127) << 23) | (fraction << 13)
    )


@fieldwise_init
struct ExrChannel(Copyable, Movable):
    """One entry of a header's channel list."""

    var name: String
    var pixel_type: ExrPixelType
    # How many pixels apart the channel's samples are, across and down.
    # One for a full-resolution channel, the only kind this reader reads.
    var x_sampling: Int
    var y_sampling: Int


struct ExrHeader(Movable):
    """What an EXR file's header says, and where its offset table starts."""

    var channels: List[ExrChannel]
    var compression: ExrCompression
    # The data window, inclusive at both ends.
    var x_min: Int
    var y_min: Int
    var x_max: Int
    var y_max: Int
    # The offset of the first entry of the line offset table.
    var start: Int

    def __init__(out self):
        """Create a header that says nothing yet."""
        self.channels = List[ExrChannel]()
        self.compression = NO_COMPRESSION
        self.x_min = 0
        self.y_min = 0
        self.x_max = -1
        self.y_max = -1
        self.start = 0

    def width(self) -> Int:
        """Return how many pixels across the data window is."""
        return self.x_max - self.x_min + 1

    def height(self) -> Int:
        """Return how many scanlines the data window holds."""
        return self.y_max - self.y_min + 1


def _need(end: Int, at: Int, count: Int) raises:
    """Refuse to read `count` bytes at `at` when fewer than that remain
    before `end`."""
    if at + count > end:
        raise Error("EXR: the file is cut short")


def _u16(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian unsigned 16-bit integer at `at`."""
    return Int(bytes[at]) | (Int(bytes[at + 1]) << 8)


def _u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian unsigned 32-bit integer at `at`."""
    return (
        Int(bytes[at])
        | (Int(bytes[at + 1]) << 8)
        | (Int(bytes[at + 2]) << 16)
        | (Int(bytes[at + 3]) << 24)
    )


def _i32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian signed 32-bit integer at `at`."""
    var value = _u32(bytes, at)
    if value >= 1 << 31:
        return value - (1 << 32)
    return value


def _string(bytes: List[UInt8], mut at: Int, end: Int) raises -> String:
    """Return the null-terminated string at `at`, moving `at` past it.

    Raises:
        Error: If no null byte comes before `end`.
    """
    var out = String()
    while True:
        if at >= end:
            raise Error("EXR: a name runs past its end")
        var byte = bytes[at]
        at += 1
        if byte == 0:
            return out^
        out += chr(Int(byte))


def _channels(
    bytes: List[UInt8], start: Int, end: Int
) raises -> List[ExrChannel]:
    """Return the channels a `chlist` attribute lists: three.js's
    `parseChlist`.

    Each entry is a name, a pixel type, a byte three.js calls `pLinear`,
    three reserved bytes, and the two samplings; a null byte ends the
    list.

    Raises:
        Error: If an entry runs past the attribute or a pixel type is none
            of the three.
    """
    var out = List[ExrChannel]()
    var at = start
    while at < end - 1:
        var name = _string(bytes, at, end)
        _need(end, at, 16)
        var kind = ExrPixelType(_i32(bytes, at))
        _ = sample_bytes(kind)
        out.append(
            ExrChannel(name, kind, _i32(bytes, at + 8), _i32(bytes, at + 12))
        )
        at += 16
    return out^


def read_header(bytes: List[UInt8]) raises -> ExrHeader:
    """Return what an EXR file's header says: three.js's `parseHeader`.

    The attributes this reader needs are `channels`, `compression` and
    `dataWindow`; every other attribute is read past by its size.

    Args:
        bytes: The whole file.

    Returns:
        The header, with `start` the offset of the line offset table.

    Raises:
        Error: If the magic number or the version is wrong, the file is
            tiled, deep or multi-part, the header is cut short, a needed
            attribute is missing or malformed, the compression is not one
            this reader reads, or the data window is empty or holds more
            pixels than any texture here.
    """
    _need(len(bytes), 0, 8)
    if _u32(bytes, 0) != MAGIC:
        raise Error("EXR: not an OpenEXR file")
    if Int(bytes[4]) != VERSION:
        raise Error("EXR: only version 2 files are read")
    if Int(bytes[5]) & (SINGLE_TILE | DEEP_DATA | MULTI_PART) != 0:
        raise Error("EXR: tiled, deep and multi-part files are not read")
    var header = ExrHeader()
    var at = 8
    var has_channels = False
    var has_compression = False
    var has_window = False
    while True:
        var name = _string(bytes, at, len(bytes))
        if name.byte_length() == 0:
            break
        var kind = _string(bytes, at, len(bytes))
        _need(len(bytes), at, 4)
        var size = _u32(bytes, at)
        at += 4
        _need(len(bytes), at, size)
        if name == "channels":
            if kind != "chlist":
                raise Error("EXR: the channels attribute must be a chlist")
            header.channels = _channels(bytes, at, at + size)
            has_channels = True
        elif name == "compression":
            if kind != "compression" or size != 1:
                raise Error("EXR: the compression attribute is malformed")
            header.compression = ExrCompression(Int(bytes[at]))
            has_compression = True
        elif name == "dataWindow":
            if kind != "box2i" or size != 16:
                raise Error("EXR: the dataWindow attribute is malformed")
            header.x_min = _i32(bytes, at)
            header.y_min = _i32(bytes, at + 4)
            header.x_max = _i32(bytes, at + 8)
            header.y_max = _i32(bytes, at + 12)
            has_window = True
        at += size
    if not has_channels:
        raise Error("EXR: the header lists no channels")
    if not has_compression:
        raise Error("EXR: the header names no compression")
    if not has_window:
        raise Error("EXR: the header names no data window")
    _ = lines_per_block(header.compression)
    if header.width() <= 0 or header.height() <= 0:
        raise Error("EXR: the data window must hold at least one pixel")
    if header.width() * header.height() > MAX_PIXELS:
        raise Error("EXR: the image has more pixels than a texture")
    header.start = at
    return header^


def _full_resolution(channel: ExrChannel) -> Bool:
    """Return True if a channel has a sample at every pixel."""
    return channel.x_sampling == 1 and channel.y_sampling == 1


def _slot(name: String, gray: Bool) -> Int:
    """Return which RGBA component a channel fills, or -1 if it is read
    past: three.js's `decodeChannels`."""
    if gray:
        if name == "Y":
            return 0
        return -1
    if name == "R":
        return 0
    if name == "G":
        return 1
    if name == "B":
        return 2
    if name == "A":
        return 3
    return -1


def _has(channels: List[ExrChannel], name: String) -> Bool:
    """Return True if a channel of that name is listed."""
    for index in range(len(channels)):
        if channels[index].name == name:
            return True
    return False


def _has_rgb(channels: List[ExrChannel]) -> Bool:
    """Return True if `R`, `G` and `B` are all listed."""
    return _has(channels, "R") and _has(channels, "G") and _has(channels, "B")


def run_length_decode(
    bytes: List[UInt8], start: Int, size: Int, expected: Int
) raises -> List[UInt8]:
    """Return what an RLE block expands to: three.js's `decodeRunLength`.

    A signed count byte: below zero, that many bytes as they stand; zero
    or above, the next byte repeated one more time than the count.

    Args:
        bytes: The whole file.
        start: Where the block's data begins.
        size: How many bytes it holds.
        expected: How many bytes it must expand to, and the most it may.

    Returns:
        The expanded bytes, still predicted and split; see `_reorder`.

    Raises:
        Error: If a run runs past the block, or the block expands past
            `expected`.
    """
    var out = List[UInt8](capacity=expected)
    var at = start
    var end = start + size
    while at < end:
        var count = Int(bytes[at])
        at += 1
        if count >= 128:
            var literal = 256 - count
            _need(end, at, literal)
            if len(out) + literal > expected:
                raise Error("EXR: a run-length block expands past its lines")
            for step in range(literal):  # pragma: no branch
                out.append(bytes[at + step])
            at += literal
            continue
        _need(end, at, 1)
        if len(out) + count + 1 > expected:
            raise Error("EXR: a run-length block expands past its lines")
        for _ in range(count + 1):  # pragma: no branch
            out.append(bytes[at])
        at += 1
    return out^


def _reorder(var data: List[UInt8]) -> List[UInt8]:
    """Undo the byte predictor and the split that RLE and ZIP apply before
    they compress: three.js's `predictor` then `interleaveScalar`.

    Each byte was stored as its difference from the one before, plus 128;
    then the even bytes were put first and the odd bytes after them.
    """
    for t in range(1, len(data)):
        data[t] = data[t - 1] + data[t] - 128
    var out = List[UInt8](length=len(data), fill=0)
    var half = (len(data) + 1) // 2
    for index in range(len(data)):
        if index % 2 == 0:
            out[index] = data[index // 2]
        else:
            out[index] = data[half + index // 2]
    return out^


struct _Bits(Movable):
    """The Huffman reader's state: an accumulator of bits not yet read, how
    many it holds, and where the next byte is, which must stay before
    `end`."""

    var c: Int
    var lc: Int
    var at: Int
    var end: Int

    def __init__(out self, at: Int, end: Int):
        """Begin reading at `at`, with nothing accumulated."""
        self.c = 0
        self.lc = 0
        self.at = at
        self.end = end

    def get_char(mut self, bytes: List[UInt8]) raises:
        """Take eight more bits into the accumulator: three.js's
        `getChar`.

        Raises:
            Error: If the next byte is past `end`.
        """
        if self.at >= self.end:
            raise Error("EXR: PIZ data is cut short")
        self.c = ((self.c << 8) | Int(bytes[self.at])) & ACCUMULATOR_MASK
        self.lc += 8
        self.at += 1

    def get_bits(mut self, bytes: List[UInt8], count: Int) raises -> Int:
        """Return the next `count` bits, most significant first: three.js's
        `getBits`.

        Raises:
            Error: If the bits run past `end`.
        """
        while self.lc < count:
            self.get_char(bytes)
        self.lc -= count
        return (self.c >> self.lc) & ((1 << count) - 1)


struct _Codes(Movable):
    """A Huffman encoding table, one length and one code per symbol, and
    the decoding table built from it.

    A short code, of `HUF_DECBITS` bits or fewer, fills every entry of the
    decoding table its bits begin; a long code lists its symbol under the
    entry its first `HUF_DECBITS` bits name. three.js's `hcode` and
    `hdecod`, with the length and the code kept apart rather than packed
    into one number.
    """

    var lengths: List[Int]
    var codes: List[Int]
    var short_length: List[Int]
    var short_symbol: List[Int]
    var long_symbols: List[List[Int]]
    # Whether any code, short or long, has claimed a decoding entry.
    var claimed: List[Bool]

    def __init__(out self):
        """Create empty tables."""
        self.lengths = List[Int](length=HUF_ENCSIZE, fill=0)
        self.codes = List[Int](length=HUF_ENCSIZE, fill=0)
        self.short_length = List[Int](length=HUF_DECSIZE, fill=0)
        self.short_symbol = List[Int](length=HUF_DECSIZE, fill=0)
        self.long_symbols = List[List[Int]](
            length=HUF_DECSIZE, fill=List[Int]()
        )
        self.claimed = List[Bool](length=HUF_DECSIZE, fill=False)

    def unpack(
        mut self, bytes: List[UInt8], mut bits: _Bits, first: Int, last: Int
    ) raises:
        """Read the packed code lengths of symbols `first` to `last`:
        three.js's `hufUnpackEncTable`.

        Six bits a symbol. A length of 63 is a long run of zeros whose
        length is the next eight bits plus six; 59 to 62 is a short run of
        two to five.

        Raises:
            Error: If the table runs past the data, or a run of zeros runs
                past `last`.
        """
        var symbol = first
        while symbol <= last:
            var length = bits.get_bits(bytes, 6)
            self.lengths[symbol] = length
            if length >= SHORT_ZEROCODE_RUN:
                var run = length - SHORT_ZEROCODE_RUN + 2
                if length == LONG_ZEROCODE_RUN:
                    run = bits.get_bits(bytes, 8) + SHORTEST_LONG_RUN
                if symbol + run > last + 1:
                    raise Error("EXR: a PIZ table's run of zeros is too long")
                for step in range(run):  # pragma: no branch
                    self.lengths[symbol + step] = 0
                symbol += run - 1
            symbol += 1
        self._canonical()

    def _canonical(mut self):
        """Give every symbol with a length its canonical code: three.js's
        `hufCanonicalCodeTable`. Longer codes take the smaller numbers."""
        var count = List[Int](length=MAX_CODE_LENGTH + 1, fill=0)
        for symbol in range(HUF_ENCSIZE):  # pragma: no branch
            count[self.lengths[symbol]] += 1
        var code = 0
        for length in range(MAX_CODE_LENGTH, 0, -1):  # pragma: no branch
            var next = (code + count[length]) >> 1
            count[length] = code
            code = next
        for symbol in range(HUF_ENCSIZE):  # pragma: no branch
            var length = self.lengths[symbol]
            if length > 0:
                self.codes[symbol] = count[length]
                count[length] += 1

    def build(mut self, first: Int, last: Int) raises:
        """Build the decoding table for symbols `first` to `last`: three.js's
        `hufBuildDecTable`.

        Raises:
            Error: If a code does not fit its length, or two codes claim
                one decoding entry.
        """
        for symbol in range(first, last + 1):
            var code = self.codes[symbol]
            var length = self.lengths[symbol]
            if code >> length != 0:
                raise Error("EXR: a PIZ code does not fit its length")
            if length > HUF_DECBITS:
                var entry = code >> (length - HUF_DECBITS)
                if self.short_length[entry] != 0:
                    raise Error("EXR: two PIZ codes share a prefix")
                self.claimed[entry] = True
                self.long_symbols[entry].append(symbol)
            elif length > 0:
                var base = code << (HUF_DECBITS - length)
                for step in range(
                    1 << (HUF_DECBITS - length)
                ):  # pragma: no branch
                    if self.claimed[base + step]:
                        raise Error("EXR: two PIZ codes share a prefix")
                    self.claimed[base + step] = True
                    self.short_length[base + step] = length
                    self.short_symbol[base + step] = symbol


def _can_fill(bits: _Bits, length: Int, end: Int) -> Bool:
    """Return True if a long code needs more bits and the data has them."""
    return bits.lc < length and bits.at < end


def _matches(codes: _Codes, symbol: Int, bits: _Bits) -> Bool:
    """Return True if the accumulator's next bits are `symbol`'s code."""
    var length = codes.lengths[symbol]
    return bits.lc >= length and codes.codes[symbol] == (
        (bits.c >> (bits.lc - length)) & ((1 << length) - 1)
    )


def _overflows(written: List[Int], run: Int, total: Int) -> Bool:
    """Return True if a run cannot be written: nothing precedes it to
    repeat, or it runs past the end."""
    return len(written) == 0 or len(written) + run > total


def _emit(
    symbol: Int,
    run_symbol: Int,
    mut bits: _Bits,
    bytes: List[UInt8],
    mut written: List[Int],
    total: Int,
) raises:
    """Write one decoded symbol: three.js's `getCode`.

    The run symbol is followed by eight bits that say how many more times
    to repeat the value before it. Any other symbol is a value.

    Raises:
        Error: If the output would run past `total`, a run has nothing
            before it, or the run's count runs past the data.
    """
    if symbol == run_symbol:
        if bits.lc < 8:
            bits.get_char(bytes)
        bits.lc -= 8
        var run = (bits.c >> bits.lc) & 0xFF
        if _overflows(written, run, total):
            raise Error("EXR: a PIZ run runs past its block")
        var repeated = written[len(written) - 1]
        for _ in range(run):
            written.append(repeated)
        return
    if len(written) >= total:
        raise Error("EXR: PIZ data runs past its block")
    written.append(symbol)


def huffman_decode(
    bytes: List[UInt8], start: Int, size: Int, total: Int
) raises -> List[Int]:
    """Return the sixteen-bit values a PIZ block's Huffman data holds:
    three.js's `hufUncompress` and `hufDecode`.

    Twenty bytes of header -- the first and last symbol of the table, and
    how many bits of code follow it -- then the packed table, then the
    codes.

    Args:
        bytes: The whole file.
        start: Where the Huffman data begins.
        size: How many bytes it holds.
        total: How many values it must decode to.

    Returns:
        The values, `total` of them.

    Raises:
        Error: If the data is cut short, the table is malformed, a code is
            not in the table, or the values do not come to `total`.
    """
    var end = start + size
    _need(end, start, 20)
    var first = _u32(bytes, start)
    var last = _u32(bytes, start + 4)
    var count = _u32(bytes, start + 12)
    if first >= HUF_ENCSIZE or last >= HUF_ENCSIZE:
        raise Error("EXR: a PIZ table names a symbol past sixteen bits")
    var bits = _Bits(start + 20, end)
    var codes = _Codes()
    codes.unpack(bytes, bits, first, last)
    if count > 8 * (end - bits.at):
        raise Error("EXR: PIZ codes run past their block")
    codes.build(first, last)
    var out = List[Int](capacity=total)
    var stop = bits.at + (count + 7) // 8
    bits.c = 0
    bits.lc = 0
    while bits.at < stop:
        bits.get_char(bytes)
        while bits.lc >= HUF_DECBITS:
            var entry = (bits.c >> (bits.lc - HUF_DECBITS)) & HUF_DECMASK
            if codes.short_length[entry] != 0:
                bits.lc -= codes.short_length[entry]
                _emit(codes.short_symbol[entry], last, bits, bytes, out, total)
                continue
            var found = False
            for index in range(len(codes.long_symbols[entry])):
                var symbol = codes.long_symbols[entry][index]
                while _can_fill(bits, codes.lengths[symbol], stop):
                    bits.get_char(bytes)
                if _matches(codes, symbol, bits):
                    bits.lc -= codes.lengths[symbol]
                    _emit(symbol, last, bits, bytes, out, total)
                    found = True
                    break
            if not found:
                raise Error("EXR: a PIZ code is not in its table")
    var spare = (8 - count) & 7
    bits.c >>= spare
    bits.lc -= spare
    while bits.lc > 0:
        var entry = (bits.c << (HUF_DECBITS - bits.lc)) & HUF_DECMASK
        if codes.short_length[entry] == 0:
            raise Error("EXR: a PIZ code is not in its table")
        bits.lc -= codes.short_length[entry]
        _emit(codes.short_symbol[entry], last, bits, bytes, out, total)
    if len(out) != total:
        raise Error("EXR: PIZ data does not fill its block")
    return out^


def _int16(value: Int) -> Int:
    """Return the low sixteen bits of `value` read as a signed number."""
    return ((value & 0xFFFF) ^ 0x8000) - 0x8000


def wavelet_pair(low: Int, high: Int, wide: Bool) -> Tuple[Int, Int]:
    """Return the two values one step of the inverse wavelet recovers:
    three.js's `wdec14`, or `wdec16` when `wide`.

    Args:
        low: The average.
        high: The difference.
        wide: Whether the values need all sixteen bits, which takes the
            modular form.

    Returns:
        The two values, before they are stored as sixteen bits.
    """
    if wide:
        var m = low & MOD_MASK
        var d = high & MOD_MASK
        var b = (m - (d >> 1)) & MOD_MASK
        var a = (d + b - A_OFFSET) & MOD_MASK
        return (a, b)
    var h = _int16(high)
    var a = _int16(low) + (h & 1) + (h >> 1)
    return (a, a - h)


def wavelet_decode(
    mut buffer: List[Int],
    j: Int,
    nx: Int,
    ox: Int,
    ny: Int,
    oy: Int,
    largest: Int,
):
    """Undo PIZ's two-dimensional Haar wavelet in place: three.js's
    `wav2Decode`, from OpenEXR.

    Args:
        buffer: The values, stored as sixteen bits each.
        j: Where this channel's first value is.
        nx: How many values across.
        ox: How far apart two values across are.
        ny: How many values down.
        oy: How far apart two values down are.
        largest: The largest value the LUT maps to; above 16383 the
            16-bit form is used.
    """
    var wide = largest >= (1 << 14)
    var n = ny if nx > ny else nx
    var p = 1
    while p <= n:
        p <<= 1
    p >>= 1
    var p2 = p
    p >>= 1
    while p >= 1:
        var py = 0
        var ey = py + oy * (ny - p2)
        var oy1 = oy * p
        var oy2 = oy * p2
        var ox1 = ox * p
        var ox2 = ox * p2
        while py <= ey:
            var px = py
            var ex = py + ox * (nx - p2)
            while px <= ex:
                var p01 = px + ox1
                var p10 = px + oy1
                var p11 = p10 + ox1
                var left = wavelet_pair(buffer[px + j], buffer[p10 + j], wide)
                var right = wavelet_pair(buffer[p01 + j], buffer[p11 + j], wide)
                var top = wavelet_pair(left[0], right[0], wide)
                buffer[px + j] = top[0] & 0xFFFF
                buffer[p01 + j] = top[1] & 0xFFFF
                var bottom = wavelet_pair(left[1], right[1], wide)
                buffer[p10 + j] = bottom[0] & 0xFFFF
                buffer[p11 + j] = bottom[1] & 0xFFFF
                px += ox2
            if nx & p != 0:
                var p10 = px + oy1
                var pair = wavelet_pair(buffer[px + j], buffer[p10 + j], wide)
                buffer[p10 + j] = pair[1] & 0xFFFF
                buffer[px + j] = pair[0] & 0xFFFF
            py += oy2
        if ny & p != 0:
            var px = py
            var ex = py + ox * (nx - p2)
            while px <= ex:
                var p01 = px + ox1
                var pair = wavelet_pair(buffer[px + j], buffer[p01 + j], wide)
                buffer[p01 + j] = pair[1] & 0xFFFF
                buffer[px + j] = pair[0] & 0xFFFF
                px += ox2
        p2 = p
        p >>= 1


def piz_decode(
    bytes: List[UInt8],
    start: Int,
    size: Int,
    width: Int,
    lines: Int,
    channels: List[ExrChannel],
) raises -> List[UInt8]:
    """Return a PIZ block's scanlines as they stand: three.js's
    `uncompressPIZ`.

    A bitmap of which sixteen-bit values occur, then Huffman-coded values
    that index a table built from the bitmap, each channel a Haar wavelet
    of its own. Decoded, inverted and looked up, the values are laid back
    out a scanline at a time, channel after channel.

    Args:
        bytes: The whole file.
        start: Where the block's data begins.
        size: How many bytes it holds.
        width: How many pixels across a scanline is.
        lines: How many scanlines the block holds.
        channels: Every channel, in the header's order.

    Returns:
        The block's bytes, as an uncompressed block holds them.

    Raises:
        Error: If the data is cut short, the bitmap is too large, or the
            Huffman data is refused by `huffman_decode`.
    """
    var end = start + size
    _need(end, start, 4)
    var smallest = _u16(bytes, start)
    var largest = _u16(bytes, start + 2)
    var at = start + 4
    if largest >= BITMAP_SIZE:
        raise Error("EXR: a PIZ bitmap is larger than sixteen bits")
    var bitmap = List[UInt8](length=BITMAP_SIZE, fill=0)
    if smallest <= largest:
        _need(end, at, largest - smallest + 1)
        for index in range(smallest, largest + 1):  # pragma: no branch
            bitmap[index] = bytes[at]
            at += 1
    # The table from a value's index back to the value: zero, then every
    # value the bitmap says occurs, in order.
    var lut = List[Int](length=USHORT_RANGE, fill=0)
    var filled = 0
    for value in range(USHORT_RANGE):  # pragma: no branch
        if value == 0 or (Int(bitmap[value >> 3]) >> (value & 7)) & 1 == 1:
            lut[filled] = value
            filled += 1
    var top = filled - 1
    _need(end, at, 4)
    var length = _u32(bytes, at)
    at += 4
    _need(end, at, length)
    var shorts = List[Int]()
    var starts = List[Int]()
    var total = 0
    for index in range(len(channels)):  # pragma: no branch
        var per = sample_bytes(channels[index].pixel_type) // 2
        shorts.append(per)
        starts.append(total)
        total += width * lines * per
    var values = huffman_decode(bytes, at, length, total)
    for index in range(len(channels)):  # pragma: no branch
        for j in range(shorts[index]):  # pragma: no branch
            wavelet_decode(
                values,
                starts[index] + j,
                width,
                shorts[index],
                lines,
                width * shorts[index],
                top,
            )
    var out = List[UInt8](capacity=total * 2)
    for line in range(lines):  # pragma: no branch
        for index in range(len(channels)):  # pragma: no branch
            var row = width * shorts[index]
            var first = starts[index] + line * row
            for step in range(row):  # pragma: no branch
                var value = lut[values[first + step]]
                out.append(UInt8(value & 0xFF))
                out.append(UInt8(value >> 8))
    return out^


def _uncompress(
    bytes: List[UInt8],
    start: Int,
    size: Int,
    expected: Int,
    lines: Int,
    header: ExrHeader,
) raises -> List[UInt8]:
    """Return a compressed block's scanlines as they stand."""
    if header.compression == NO_COMPRESSION:
        raise Error("EXR: an uncompressed block is cut short")
    if header.compression == RLE_COMPRESSION:
        return _reorder(run_length_decode(bytes, start, size, expected))
    if header.compression == PIZ_COMPRESSION:
        return piz_decode(
            bytes, start, size, header.width(), lines, header.channels
        )
    return _reorder(
        zlib_inflate(List[UInt8](bytes[start : start + size]), expected)
    )


def decode(bytes: List[UInt8]) raises -> FloatImage:
    """Return the image an EXR file holds, as linear floats.

    Args:
        bytes: The whole file.

    Returns:
        The image, RGBA from the top row of the data window down.

    Raises:
        Error: Everything `read_header` raises; if a channel is
            subsampled, the channels are neither `R`, `G` and `B` nor `Y`,
            the image is luminance-chroma, or a color channel is `UINT`;
            or if a block is cut short, names a line outside the image,
            or does not expand to its lines.
    """
    var header = read_header(bytes)
    ref channels = header.channels
    for index in range(len(channels)):
        if not _full_resolution(channels[index]):
            raise Error("EXR: subsampled channels are not read")
    var gray = False
    if not _has_rgb(channels):
        if _has(channels, "RY") or _has(channels, "BY"):
            raise Error("EXR: luminance-chroma images (RY and BY) are not read")
        if not _has(channels, "Y"):
            raise Error("EXR: an image needs R, G and B channels, or Y")
        gray = True
    var width = header.width()
    var height = header.height()
    var slots = List[Int]()
    var offsets = List[Int]()
    var line_bytes = 0
    for index in range(len(channels)):  # pragma: no branch
        var slot = _slot(channels[index].name, gray)
        if slot >= 0 and channels[index].pixel_type == UINT_SAMPLES:
            raise Error("EXR: a color channel must be HALF or FLOAT")
        slots.append(slot)
        offsets.append(line_bytes)
        line_bytes += sample_bytes(channels[index].pixel_type)
    # Alpha is one where the file has none, and everything else is
    # written below: three.js fills the whole image with ones.
    var fill = Float32(0)
    if gray or not _has(channels, "A"):
        fill = 1
    var pixels = List[Float32](length=width * height * 4, fill=fill)
    var per_block = lines_per_block(header.compression)
    var blocks = (height + per_block - 1) // per_block
    var at = header.start + 8 * blocks
    _need(len(bytes), header.start, 8 * blocks)
    for _ in range(blocks):  # pragma: no branch
        _need(len(bytes), at, 8)
        var line = _i32(bytes, at) - header.y_min
        var size = _u32(bytes, at + 4)
        at += 8
        if line < 0 or line >= height:
            raise Error("EXR: a block names a line outside the image")
        var lines = min(per_block, height - line)
        var expected = lines * width * line_bytes
        _need(len(bytes), at, size)
        var raw: List[UInt8]
        if size >= expected:
            raw = List[UInt8](bytes[at : at + expected])
        else:
            raw = _uncompress(bytes, at, size, expected, lines, header)
        if len(raw) != expected:
            raise Error("EXR: a block does not expand to its lines")
        at += size
        for row in range(lines):  # pragma: no branch
            var y = line + row
            for index in range(len(channels)):  # pragma: no branch
                var slot = slots[index]
                if slot < 0:
                    continue
                var base = row * width * line_bytes + offsets[index] * width
                for x in range(width):  # pragma: no branch
                    var value: Float32
                    if channels[index].pixel_type == HALF_SAMPLES:
                        var at_sample = base + x * 2
                        value = half_to_float(
                            UInt16(raw[at_sample])
                            | (UInt16(raw[at_sample + 1]) << 8)
                        )
                    else:
                        var at_sample = base + x * 4
                        value = float_from_bytes(
                            raw[at_sample],
                            raw[at_sample + 1],
                            raw[at_sample + 2],
                            raw[at_sample + 3],
                        )
                    pixels[(y * width + x) * 4 + slot] = value
    if gray:
        for pixel in range(width * height):  # pragma: no branch
            pixels[pixel * 4 + 1] = pixels[pixel * 4]
            pixels[pixel * 4 + 2] = pixels[pixel * 4]
    return FloatImage(width, height, pixels^)
