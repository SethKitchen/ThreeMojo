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
ZIPS, ZIP, PIZ, PXR24, B44, B44A, DWAA or DWAB. An image with `R`, `G` and `B` becomes RGBA, with `A` as
its alpha or one where it has none; an image with `Y` alone becomes gray,
alpha one. Any other channel is read past. This is three.js's default
`RGBAFormat` output. three.js's default `type` is `HalfFloatType`; the
reader returns floats, which hold every half exactly and every float as it
is, as three.js's `FloatType` output does.

**What is not.** Tiled, deep and multi-part files; luminance-chroma images with `RY` and `BY`, whose
chroma is stored at a quarter of the resolution; subsampled channels; and
`UINT` color channels. This reader refuses each by name.
three.js does not read `UINT` color either.

**Where it differs from three.js, it refuses rather than guesses.** three.js
reads every color channel with the pixel type of the last one it met, so a
file of half red and float alpha misreads one of them; this reader reads
each channel as its own type. three.js ignores a channel's sampling and
misreads a subsampled one; this reader refuses it. three.js reads past the
end of a block, a Huffman table or the file as whatever the array holds
there; this reader refuses each. A block that names a line outside the
image is refused, and so is a block that does not expand to its lines.

**Codec references.** PXR24 and DWA target three.js r180; B44/B44A target
r186. The arithmetic and channel layout follow OpenEXR 3.1.5, including
round-to-nearest half conversion, pLinear, layered DWA color groups,
lossless unknown channels, and DWA versions zero through two. The decoder
supports both static-Huffman and DEFLATE AC streams. Independent fixtures
and reproducible three.js counterexamples are in `assets/exr_codecs/`.
DWA does not copy the JavaScript decoder's mixed-channel, grayscale,
unknown-stream or pLinear defects. Nonfinite DCT coefficients are refused.

The rows come out from the top, the first line of the data window first,
as every other reader here returns them. three.js flips them and marks the
texture `flipY = false`, which samples the same way.
"""

from render.float_image import FloatImage
from render.inflate import zlib_inflate
from render.png import MAX_PIXELS
from render.texture import float_from_bytes
from std.memory import bitcast
from std.collections import Dict
from std.math import cos, log, pow

# The first four bytes of every OpenEXR file, as a little-endian integer.
comptime MAGIC = 20000630
"""The little-endian magic number of an OpenEXR file."""
# The only file version there is.
comptime VERSION = 2
"""The supported OpenEXR file version."""
# The version field's flag bits for the layouts this reader does not read.
comptime SINGLE_TILE = 0x02
"""The tiled-image version flag."""
comptime DEEP_DATA = 0x08
"""The deep-image version flag."""
comptime MULTI_PART = 0x10
"""The multipart-image version flag."""

# PIZ's constants, named as OpenEXR and three.js name them.
comptime USHORT_RANGE = 1 << 16
"""The number of distinct sixteen-bit values."""
comptime BITMAP_SIZE = USHORT_RANGE >> 3
"""The number of bytes in a full PIZ value bitmap."""
comptime HUF_ENCBITS = 16
"""The width of a Huffman symbol in bits."""
comptime HUF_DECBITS = 14
"""The number of bits in a Huffman decoding-table index."""
comptime HUF_ENCSIZE = (1 << HUF_ENCBITS) + 1
"""The number of Huffman symbols, including the run marker."""
comptime HUF_DECSIZE = 1 << HUF_DECBITS
"""The number of entries in the short-code decoding table."""
comptime HUF_DECMASK = HUF_DECSIZE - 1
"""The mask for a short-code decoding-table index."""
comptime SHORT_ZEROCODE_RUN = 59
"""The first short zero-length-run marker."""
comptime LONG_ZEROCODE_RUN = 63
"""The long zero-length-run marker."""
comptime SHORTEST_LONG_RUN = 2 + LONG_ZEROCODE_RUN - SHORT_ZEROCODE_RUN
"""The minimum zero-length run encoded by a long marker."""
# The longest code length a packed table can spell: six bits, less the
# five values that mean a run of zeros.
comptime MAX_CODE_LENGTH = 58
"""The maximum Huffman code length."""
# How many bits of the Huffman reader's accumulator are kept. Only the
# bits not yet consumed matter, and a code is never longer than
# `MAX_CODE_LENGTH`, so this is room enough and no shift can overflow.
comptime ACCUMULATOR_MASK = (1 << 62) - 1
"""The mask that keeps the bit accumulator bounded."""
# The two wavelet decoders: 14-bit when every value fits, 16-bit else.
comptime A_OFFSET = 1 << 15
"""The offset in the sixteen-bit PIZ wavelet."""
comptime MOD_MASK = (1 << 16) - 1
"""The sixteen-bit modular arithmetic mask."""
# Bound each decoded stream and coefficient allocation in bytes. DWA's
# padded 8-by-8 blocks can have far more coefficients than real pixels.
comptime _MAX_EXR_STREAM_BYTES = MAX_PIXELS * 4


@fieldwise_init
struct ExrCompression(Equatable, ImplicitlyCopyable, Writable):
    """How an EXR file's blocks are compressed, as a type: the header's
    `compression` byte.

    See `core.object3d.NodeId` for why it is wrapped. The type does not
    stop `ExrCompression(10)`, so `lines_per_block` asks `is_valid`.
    """

    var value: Int
    """The stored format code."""

    def is_valid(self) -> Bool:
        """Return True if this is a scanline compression code from zero to nine.

        Returns:
            Whether the code names a supported scanline compression.
        """
        return self.value >= NO_COMPRESSION.value and (
            self.value <= DWAB_COMPRESSION.value
        )


# Each scanline as it stands, one to a block.
comptime NO_COMPRESSION = ExrCompression(0)
"""Uncompressed samples, one scanline per block."""
# Run-length encoded bytes, one scanline to a block.
comptime RLE_COMPRESSION = ExrCompression(1)
"""Run-length compression, one scanline per block."""
# zlib, one scanline to a block.
comptime ZIPS_COMPRESSION = ExrCompression(2)
"""ZIP compression, one scanline per block."""
# zlib, sixteen scanlines to a block.
comptime ZIP_COMPRESSION = ExrCompression(3)
"""ZIP compression, sixteen scanlines per block."""
# A wavelet and Huffman coding, thirty-two scanlines to a block.
comptime PIZ_COMPRESSION = ExrCompression(4)
"""PIZ wavelet compression, thirty-two scanlines per block."""
# zlib over channel deltas, with float mantissas reduced to 24 bits.
comptime PXR24_COMPRESSION = ExrCompression(5)
"""PXR24 compression: sixteen scanlines per block."""
# Lossy half blocks, with an optional short constant block in B44A.
comptime B44_COMPRESSION = ExrCompression(6)
"""B44 half compression: thirty-two scanlines per block."""
comptime B44A_COMPRESSION = ExrCompression(7)
"""B44 with short flat blocks: thirty-two scanlines per block."""
# Lossy DCT color, with lossless alpha and other channels.
comptime DWAA_COMPRESSION = ExrCompression(8)
"""DWA compression: thirty-two scanlines per block."""
comptime DWAB_COMPRESSION = ExrCompression(9)
"""DWA compression: 256 scanlines per block."""


def lines_per_block(compression: ExrCompression) raises -> Int:
    """Return how many scanlines one block of a compression holds.

    Args:
        compression: One of the ten supported scanline compressions.

    Returns:
        One for none, RLE and ZIPS; sixteen for ZIP and PXR24;
        thirty-two for PIZ, B44, B44A and DWAA; 256 for DWAB.

    Raises:
        Error: If the compression is not one this reader reads.
    """
    if not compression.is_valid():
        raise Error("EXR: invalid scanline compression code")
    if compression == ZIP_COMPRESSION or compression == PXR24_COMPRESSION:
        return 16
    if compression == DWAB_COMPRESSION:
        return 256
    if compression.value >= PIZ_COMPRESSION.value:
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
    """The stored format code."""

    def is_valid(self) -> Bool:
        """Return True if this is `UINT_SAMPLES`, `HALF_SAMPLES` or
        `FLOAT_SAMPLES`.

        Returns:
            Whether the code names a defined sample representation.
        """
        return (
            self == UINT_SAMPLES
            or self == HALF_SAMPLES
            or self == FLOAT_SAMPLES
        )


# An unsigned 32-bit integer: an id, not light. Read past, never shown.
comptime UINT_SAMPLES = ExrPixelType(0)
"""Unsigned integer samples, four bytes each."""
# An IEEE 754 half, two bytes.
comptime HALF_SAMPLES = ExrPixelType(1)
"""IEEE half-float samples, two bytes each."""
# An IEEE 754 single, four bytes.
comptime FLOAT_SAMPLES = ExrPixelType(2)
"""IEEE single-precision samples, four bytes each."""


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


struct ExrChannel(Copyable, Movable):
    """One entry of a header's channel list."""

    var name: String
    """The channel name, including its optional layer prefix."""
    var pixel_type: ExrPixelType
    """The channel sample representation."""
    # How many pixels apart the channel's samples are, across and down.
    # One for a full-resolution channel, the only kind this reader reads.
    var x_sampling: Int
    """Horizontal sample spacing in pixels."""
    var y_sampling: Int
    """Vertical sample spacing in scanlines."""
    # B44 and DWA use this flag for their perceptual transfer functions.
    var p_linear: Bool
    """Whether this channel's samples are perceptually linear."""

    def __init__(
        out self,
        name: String,
        pixel_type: ExrPixelType,
        x_sampling: Int,
        y_sampling: Int,
        p_linear: Bool = False,
    ):
        """Create a channel descriptor.

        Args:
            name: The channel name, including any layer prefix.
            pixel_type: The on-disk sample type.
            x_sampling: Horizontal sample spacing.
            y_sampling: Vertical sample spacing.
            p_linear: Whether the samples are perceptually linear.
        """
        self.name = name
        self.pixel_type = pixel_type
        self.x_sampling = x_sampling
        self.y_sampling = y_sampling
        self.p_linear = p_linear


struct ExrHeader(Movable):
    """What an EXR file's header says, and where its offset table starts."""

    var channels: List[ExrChannel]
    """The channels in their on-disk order."""
    var compression: ExrCompression
    """The scanline compression method."""
    # The data window, inclusive at both ends.
    var x_min: Int
    """The first column of the data window."""
    var y_min: Int
    """The first scanline of the data window."""
    var x_max: Int
    """The last column of the data window."""
    var y_max: Int
    """The last scanline of the data window."""
    # The offset of the first entry of the line offset table.
    var start: Int
    """The byte offset of the scanline offset table."""

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
        """Return the width of the data window.

        Returns:
            The number of columns in the inclusive window.
        """
        return self.x_max - self.x_min + 1

    def height(self) -> Int:
        """Return the height of the data window.

        Returns:
            The number of scanlines in the inclusive window.
        """
        return self.y_max - self.y_min + 1


def _need(end: Int, at: Int, count: Int) raises:
    """Refuse to read `count` bytes at `at` when fewer than that remain
    before `end`."""
    if at < 0 or count < 0 or at > end or count > end - at:
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
    var seen = Dict[String, Bool]()
    var at = start
    while at < end - 1:
        var name = _string(bytes, at, end)
        _need(end, at, 16)
        if name.byte_length() == 0 or name in seen:
            raise Error("EXR: empty or duplicate channel name")
        seen[name] = True
        if bytes[at + 4] > 1:
            raise Error("EXR: pLinear must be zero or one")
        var kind = ExrPixelType(_i32(bytes, at))
        _ = sample_bytes(kind)
        out.append(
            ExrChannel(
                name,
                kind,
                _i32(bytes, at + 8),
                _i32(bytes, at + 12),
                bytes[at + 4] != 0,
            )
        )
        at += 16
    if at != end - 1 or bytes[at] != 0:
        raise Error("EXR: the channel list has no final null byte")
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
    if header.width() > MAX_PIXELS // header.height():
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


def _store_word(mut out: List[UInt8], at: Int, bits: Int, width: Int):
    """Store the low bytes of a word at an already checked output offset."""
    for byte in range(width):
        out[at + byte] = UInt8((bits >> (8 * byte)) & 255)


def _channel_bytes(channels: List[ExrChannel]) raises -> Int:
    """Return a bounded number of bytes per full-resolution pixel."""
    var total = 0
    for channel in channels:
        total += sample_bytes(channel.pixel_type)
    if total > MAX_PIXELS:
        raise Error("EXR: the channel layout is too large")
    return total


def _block_bytes(
    width: Int, lines: Int, channels: List[ExrChannel]
) raises -> Int:
    """Bound a decoded block before multiplying or allocating its storage."""
    var per = _channel_bytes(channels)
    if width <= 0 or lines <= 0 or per == 0:
        raise Error("EXR: invalid block dimensions or channels")
    # The output image has the same four-byte sample budget. Bound all
    # intermediate channels too, including channels omitted from RGBA.
    if width > MAX_PIXELS // lines or per > (MAX_PIXELS * 4) // (width * lines):
        raise Error("EXR: the decoded block is too large")
    return width * lines * per


def _inflate_exact(
    bytes: List[UInt8], at: Int, size: Int, expected: Int
) raises -> List[UInt8]:
    """Inflate a checked range and require the declared output length."""
    _need(len(bytes), at, size)
    if expected < 0 or expected > _MAX_EXR_STREAM_BYTES:
        raise Error("EXR: a decoded stream exceeds its byte budget")
    if size == 0:
        if expected != 0:
            raise Error("EXR: a compressed stream is missing")
        return List[UInt8]()
    var out = zlib_inflate(List[UInt8](bytes[at : at + size]), expected)
    if len(out) != expected:
        raise Error("EXR: a compressed stream has the wrong length")
    return out^


def _pxr24_decode(
    bytes: List[UInt8],
    start: Int,
    size: Int,
    width: Int,
    lines: Int,
    channels: List[ExrChannel],
) raises -> List[UInt8]:
    """Decode OpenEXR 3.1.5 PXR24's byte planes and modular deltas."""
    var expected = _block_bytes(width, lines, channels)
    var packed_per = 0
    for channel in channels:
        packed_per += (
            3 if channel.pixel_type
            == FLOAT_SAMPLES else sample_bytes(channel.pixel_type)
        )
    var packed = _inflate_exact(bytes, start, size, width * lines * packed_per)
    var out = List[UInt8](length=expected, fill=0)
    var src = 0
    var dst = 0
    for _ in range(lines):
        for channel in channels:
            var wide = sample_bytes(channel.pixel_type)
            var planes = 3 if channel.pixel_type == FLOAT_SAMPLES else wide
            var pixel = UInt32(0)
            for x in range(width):
                var delta = UInt32(0)
                for plane in range(planes):
                    delta = (delta << 8) | UInt32(
                        packed[src + plane * width + x]
                    )
                if channel.pixel_type == FLOAT_SAMPLES:
                    delta <<= 8
                pixel += delta
                _store_word(out, dst, Int(pixel), wide)
                dst += wide
            src += planes * width
    return out^


def _half_bits(value: Float32) -> Int:
    """Round to IEEE half, ties to even, as the OpenEXR reference does."""
    return Int(bitcast[DType.uint16](Float16(value)))


def _b44_linear(bits: Int) -> Int:
    """Evaluate the OpenEXR 3.1.5 half-to-half B44 log lookup."""
    if bits & 0x7C00 == 0x7C00 or bits > 0x8000:
        return 0
    # Both positive and negative zero map to negative infinity in the
    # reference table. The final texture boundary retains its finite check.
    return _half_bits(Float32(8 * log(Float64(half_to_float(UInt16(bits))))))


def _b44_decode(
    bytes: List[UInt8],
    start: Int,
    size: Int,
    width: Int,
    lines: Int,
    channels: List[ExrChannel],
) raises -> List[UInt8]:
    """Decode B44/B44A 4-by-4 half blocks and verbatim other channels."""
    _need(len(bytes), start, size)
    var end = start + size
    var expected = _block_bytes(width, lines, channels)
    var per = _channel_bytes(channels)
    var out = List[UInt8](length=expected, fill=0)
    var at = start
    var offset = 0
    var block = List[Int](length=16, fill=0)
    for channel in channels:
        var wide = sample_bytes(channel.pixel_type)
        if channel.pixel_type != HALF_SAMPLES:
            _need(end, at, width * lines * wide)
            for y in range(lines):
                for x in range(width * wide):
                    out[y * width * per + offset * width + x] = bytes[at]
                    at += 1
        else:
            for by in range(0, lines, 4):
                for bx in range(0, width, 4):
                    _need(end, at, 3)
                    block[0] = (Int(bytes[at]) << 8) | Int(bytes[at + 1])
                    var shift = Int(bytes[at + 2]) >> 2
                    # OpenEXR uses the same reader for both compression
                    # tags. Every impossible shift denotes a flat block.
                    if shift >= 13:
                        for i in range(1, 16):
                            block[i] = block[0]
                        at += 3
                    else:
                        _need(end, at, 14)
                        for delta_index in range(15):
                            var bit = 22 + delta_index * 6
                            var word = Int(bytes[at + bit // 8]) << 8
                            if bit % 8 > 2:
                                word |= Int(bytes[at + bit // 8 + 1])
                            var delta = ((word >> (10 - bit % 8)) & 63) - 32
                            var dest = (
                                delta_index + 1
                            ) * 4 if delta_index < 3 else (
                                (delta_index - 3) % 4
                            ) * 4 + (
                                delta_index - 3
                            ) // 4 + 1
                            var source = (
                                dest - 4 if delta_index < 3 else dest - 1
                            )
                            block[dest] = (
                                block[source] + (delta << shift)
                            ) & 0xFFFF
                        at += 14
                    for i in range(16):
                        var bits = block[i]
                        bits = (
                            bits & 0x7FFF if bits & 0x8000 else (~bits) & 0xFFFF
                        )
                        if channel.p_linear:
                            bits = _b44_linear(bits)
                        var x = bx + i % 4
                        var y = by + i // 4
                        if x < width and y < lines:
                            _store_word(
                                out,
                                y * width * per + offset * width + x * 2,
                                bits,
                                2,
                            )
        offset += wide
    if at != end:
        raise Error("EXR: a B44 block has trailing bytes")
    return out^


@fieldwise_init
struct _DwaScheme(Equatable, ImplicitlyCopyable):
    """The three per-channel schemes in a DWA rule."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this names UNKNOWN, LOSSY_DCT or RLE."""
        return self.value >= 0 and self.value <= 2


comptime _DWA_UNKNOWN = _DwaScheme(0)
comptime _DWA_DCT = _DwaScheme(1)
comptime _DWA_RLE = _DwaScheme(2)


@fieldwise_init
struct _DwaAcCompression(Equatable, ImplicitlyCopyable):
    """The entropy coding of DWA AC tokens."""

    var value: Int

    def is_valid(self) -> Bool:
        """Return whether this names static Huffman or zlib."""
        return self.value == 0 or self.value == 1


comptime _DWA_HUFFMAN = _DwaAcCompression(0)
comptime _DWA_DEFLATE = _DwaAcCompression(1)


@fieldwise_init
struct _DwaRule(Copyable, Movable):
    """A validated DWA suffix, sample type, scheme and color component."""

    var suffix: String
    var pixel_type: ExrPixelType
    var scheme: _DwaScheme
    var csc: Int
    var insensitive: Bool


def _dwa_counter(bytes: List[UInt8], at: Int, limit: Int) raises -> Int:
    """Read a little-endian counter only if it fits a derived size limit."""
    var lo = _u32(bytes, at)
    if _u32(bytes, at + 4) != 0 or lo > limit:
        raise Error("EXR: a DWA counter exceeds its bounded layout")
    return lo


def _dwa_rules(
    bytes: List[UInt8], mut at: Int, end: Int, version: Int
) raises -> List[_DwaRule]:
    """Read version-two rules or construct the legacy case-insensitive set."""
    var rules = List[_DwaRule]()
    if version < 2:
        var names: List[String] = [
            "r",
            "red",
            "g",
            "grn",
            "green",
            "b",
            "blu",
            "blue",
            "y",
            "by",
            "ry",
            "a",
        ]
        for i in range(len(names)):
            var csc = -1
            if i < 2:
                csc = 0
            elif i < 5:
                csc = 1
            elif i < 8:
                csc = 2
            for type in range(3):
                if i == 11 or type != 0:
                    rules.append(
                        _DwaRule(
                            names[i],
                            ExrPixelType(type),
                            _DWA_RLE if i == 11 else _DWA_DCT,
                            csc,
                            True,
                        )
                    )
        return rules^
    _need(end, at, 2)
    var size = _u16(bytes, at)
    if size < 2:
        raise Error("EXR: a DWA rule table is too short")
    _need(end, at, size)
    var stop = at + size
    at += 2
    while at < stop:
        var suffix = _string(bytes, at, stop)
        _need(stop, at, 2)
        var packed = Int(bytes[at])
        var scheme = _DwaScheme((packed >> 2) & 3)
        var csc = (packed >> 4) - 1
        var kind = ExrPixelType(Int(bytes[at + 1]))
        if (
            not scheme.is_valid()
            or csc < -1
            or csc > 2
            or not kind.is_valid()
            or packed & 2 != 0
        ):
            raise Error("EXR: an invalid DWA channel rule")
        if scheme == _DWA_DCT and kind == UINT_SAMPLES:
            raise Error("EXR: DWA DCT channels must be HALF or FLOAT")
        rules.append(_DwaRule(suffix, kind, scheme, csc, packed & 1 != 0))
        at += 2
    return rules^


def _dwa_prefix(name: String) -> Tuple[String, String]:
    """Separate a channel's last dot suffix from its layer prefix."""
    var dot = -1
    for i in range(name.byte_length()):
        if name.as_bytes()[i] == 46:
            dot = i
    if dot < 0:
        return (String(), name)
    return (String(name[byte=:dot]), String(name[byte = dot + 1 :]))


def _dwa_linear(bits: Int) -> Int:
    """Evaluate the OpenEXR 3.1.5 nonlinear-half to linear-half lookup."""
    if bits & 0x7C00 == 0x7C00:
        return 0
    var value = half_to_float(UInt16(bits))
    var magnitude = abs(value)
    var linear: Float64
    if magnitude <= 1:
        linear = pow(Float64(magnitude), Float64(Float32(2.2)))
    else:
        var base = Float32(pow(Float64(2.7182818), Float64(2.2)))
        linear = pow(Float64(base), Float64(magnitude - 1))
    if value < 0:
        linear = -linear
    return _half_bits(Float32(linear))


def _dwa_inverse_dct(mut data: List[Float32]):
    """Invert a DCT using the pinned OpenEXR scalar factorization."""
    var a = Float32(0.5) * cos(Float32(3.14159) / 4)
    var b = Float32(0.5) * cos(Float32(3.14159) / 16)
    var c = Float32(0.5) * cos(Float32(3.14159) / 8)
    var d = Float32(0.5) * cos(Float32(3) * Float32(3.14159) / 16)
    var e = Float32(0.5) * cos(Float32(5) * Float32(3.14159) / 16)
    var f = Float32(0.5) * cos(Float32(3) * Float32(3.14159) / 8)
    var g = Float32(0.5) * cos(Float32(7) * Float32(3.14159) / 16)
    for pass_index in range(2):
        for line in range(8):
            var base = line * 8 if pass_index == 0 else line
            var stride = 1 if pass_index == 0 else 8
            var v0 = data[base]
            var v1 = data[base + stride]
            var v2 = data[base + 2 * stride]
            var v3 = data[base + 3 * stride]
            var v4 = data[base + 4 * stride]
            var v5 = data[base + 5 * stride]
            var v6 = data[base + 6 * stride]
            var v7 = data[base + 7 * stride]
            var beta0 = b * v1 + d * v3 + e * v5 + g * v7
            var beta1 = d * v1 - g * v3 - b * v5 - e * v7
            var beta2 = e * v1 - b * v3 + g * v5 + d * v7
            var beta3 = g * v1 - e * v3 + d * v5 - b * v7
            var theta0 = a * (v0 + v4)
            var theta3 = a * (v0 - v4)
            var theta1 = c * v2 + f * v6
            var theta2 = f * v2 - c * v6
            var gamma0 = theta0 + theta1
            var gamma1 = theta3 + theta2
            var gamma2 = theta3 - theta2
            var gamma3 = theta0 - theta1
            data[base] = gamma0 + beta0
            data[base + stride] = gamma1 + beta1
            data[base + 2 * stride] = gamma2 + beta2
            data[base + 3 * stride] = gamma3 + beta3
            data[base + 4 * stride] = gamma3 - beta3
            data[base + 5 * stride] = gamma2 - beta2
            data[base + 6 * stride] = gamma1 - beta1
            data[base + 7 * stride] = gamma0 - beta0


def _dwa_dct_block(
    ac: List[Int], mut at: Int, dc: Int, zigzag: List[Int]
) raises -> List[Float32]:
    """Read one bounded 8-by-8 AC token sequence and invert its DCT."""
    var data = List[Float32](length=64, fill=0)
    data[0] = half_to_float(UInt16(dc))
    var pos = 1
    var nonzero = False
    while pos < 64:
        if at >= len(ac):
            raise Error("EXR: DWA AC data does not fill its block")
        var token = ac[at]
        at += 1
        if token == 0xFF00:
            break
        if token >> 8 == 0xFF:
            var run = token & 255
            if run > 64 - pos:
                raise Error("EXR: a DWA AC run exceeds its block")
            pos += run
        else:
            if token & 0x7C00 == 0x7C00:
                raise Error("EXR: a DWA coefficient is not finite")
            data[zigzag[pos]] = half_to_float(UInt16(token))
            pos += 1
            nonzero = True
    if dc & 0x7C00 == 0x7C00:
        raise Error("EXR: a DWA coefficient is not finite")
    if nonzero:
        _dwa_inverse_dct(data)
    else:
        # This is the reference's dedicated DC-only path.
        var value = data[0] * Float32(0.3535536) * Float32(0.3535536)
        for i in range(64):
            data[i] = value
    return data^


def _dwa_group(
    mut out: List[UInt8],
    ac: List[Int],
    dc: List[Int],
    mut ac_at: Int,
    mut dc_at: Int,
    group: List[Int],
    channels: List[ExrChannel],
    offsets: List[Int],
    width: Int,
    lines: Int,
    per: Int,
) raises:
    """Decode one RGB layer or one standalone DCT channel."""
    var blocks_x = (width + 7) // 8
    var blocks_y = (lines + 7) // 8
    var blocks = blocks_x * blocks_y
    var components = len(group)
    if dc_at > len(dc) or components * blocks > len(dc) - dc_at:
        raise Error("EXR: DWA DC data does not fill its channels")
    var zigzag: List[Int] = [
        0,
        1,
        8,
        16,
        9,
        2,
        3,
        10,
        17,
        24,
        32,
        25,
        18,
        11,
        4,
        5,
        12,
        19,
        26,
        33,
        40,
        48,
        41,
        34,
        27,
        20,
        13,
        6,
        7,
        14,
        21,
        28,
        35,
        42,
        49,
        56,
        57,
        50,
        43,
        36,
        29,
        22,
        15,
        23,
        30,
        37,
        44,
        51,
        58,
        59,
        52,
        45,
        38,
        31,
        39,
        46,
        53,
        60,
        61,
        54,
        47,
        55,
        62,
        63,
    ]
    for by in range(blocks_y):
        for bx in range(blocks_x):
            var values = List[List[Float32]]()
            for component in range(components):
                values.append(
                    _dwa_dct_block(
                        ac,
                        ac_at,
                        dc[dc_at + component * blocks + by * blocks_x + bx],
                        zigzag,
                    )
                )
            for y in range(min(8, lines - by * 8)):
                for x in range(min(8, width - bx * 8)):
                    var i = y * 8 + x
                    if components == 3:
                        var y_value = values[0][i]
                        var cb = values[1][i]
                        var cr = values[2][i]
                        values[0][i] = y_value + Float32(1.5747) * cr
                        values[1][i] = (
                            y_value
                            - Float32(0.1873) * cb
                            - Float32(0.4682) * cr
                        )
                        values[2][i] = y_value + Float32(1.8556) * cb
                    for component in range(components):
                        var channel = group[component]
                        var bits = _half_bits(values[component][i])
                        if components == 3 or not channels[channel].p_linear:
                            bits = _dwa_linear(bits)
                        var wide = sample_bytes(channels[channel].pixel_type)
                        var at = (
                            (by * 8 + y) * width * per
                            + offsets[channel] * width
                            + (bx * 8 + x) * wide
                        )
                        if wide == 4:
                            bits = Int(
                                bitcast[DType.uint32](
                                    half_to_float(UInt16(bits))
                                )
                            )
                        _store_word(out, at, bits, wide)
    dc_at += components * blocks


def _dwa_lower(name: String) -> String:
    """Fold ASCII only, as OpenEXR's rules do in the C locale."""
    var out = String()
    for codepoint in name.codepoint_slices():
        var text = String(codepoint)
        if text.byte_length() == 1:
            var byte = Int(text.as_bytes()[0])
            if byte >= 65 and byte <= 90:
                out += chr(byte + 32)
                continue
        out += text
    return out^


def _sort_dwa_prefixes(mut items: List[String]):
    """Sort layer prefixes in O(n log n) comparisons, without recursion."""
    var scratch = List[String](length=len(items), fill=String())
    var step = 1
    while step < len(items):
        for start in range(0, len(items), step * 2):
            var middle = min(start + step, len(items))
            var end = min(start + step * 2, len(items))
            var left = start
            var right = middle
            for dest in range(start, end):
                if left < middle and (
                    right >= end or items[left] <= items[right]
                ):
                    scratch[dest] = items[left]
                    left += 1
                else:
                    scratch[dest] = items[right]
                    right += 1
        for i in range(len(items)):
            items[i] = scratch[i]
        step *= 2


def _dwa_decode(
    bytes: List[UInt8],
    start: Int,
    size: Int,
    width: Int,
    lines: Int,
    channels: List[ExrChannel],
) raises -> List[UInt8]:
    """Decode DWA versions zero through two with layout-derived bounds."""
    _need(len(bytes), start, size)
    var end = start + size
    _need(end, start, 88)
    var expected = _block_bytes(width, lines, channels)
    var version = _dwa_counter(bytes, start, 2)
    var unknown_size = _dwa_counter(bytes, start + 8, expected)
    var unknown_compressed = _dwa_counter(bytes, start + 16, size)
    var ac_compressed = _dwa_counter(bytes, start + 24, size)
    var dc_compressed = _dwa_counter(bytes, start + 32, size)
    var rle_compressed = _dwa_counter(bytes, start + 40, size)
    var rle_size = _dwa_counter(bytes, start + 48, expected * 2)
    var rle_raw = _dwa_counter(bytes, start + 56, expected)
    var ac_mode = _DwaAcCompression(_dwa_counter(bytes, start + 80, 1))
    if not ac_mode.is_valid():
        raise Error("EXR: invalid DWA AC compression")
    var at = start + 88
    var rules = _dwa_rules(bytes, at, end, version)
    var sizes: List[Int] = [
        unknown_compressed,
        ac_compressed,
        dc_compressed,
        rle_compressed,
    ]
    var starts = List[Int]()
    for count in sizes:
        _need(end, at, count)
        starts.append(at)
        at += count
    if at != end:
        raise Error("EXR: DWA streams have trailing bytes")
    # Index rules once. Keep both their last matching position and every
    # CSC assignment. This preserves overlapping rules without a rules x
    # channels scan, and later channels still overwrite the same CSC slot.
    var exact = Dict[String, Tuple[Int, Int]]()
    var folded = Dict[String, Tuple[Int, Int]]()
    for index in range(len(rules)):
        ref rule = rules[index]
        var key = String(rule.pixel_type.value) + rule.suffix
        var mask = 0 if rule.csc < 0 else 1 << rule.csc
        if rule.insensitive:
            # Serialized rules already contain their intended folded
            # suffix. OpenEXR folds the candidate, not this stored value.
            var previous = folded.get(key, (-1, 0))
            folded[key] = (index, previous[1] | mask)
        else:
            var previous = exact.get(key, (-1, 0))
            exact[key] = (index, previous[1] | mask)
    var schemes = List[_DwaScheme]()
    var prefix_indices = Dict[String, Int]()
    var group_prefixes = List[String]()
    var candidates = List[List[Int]]()
    var offsets = List[Int]()
    var per = 0
    var dct_channels = 0
    var unknown_expected = 0
    var rle_expected = 0
    for channel_index in range(len(channels)):
        ref channel = channels[channel_index]
        var names = _dwa_prefix(channel.name)
        var group_index = prefix_indices.get(names[0], -1)
        if group_index < 0:
            group_index = len(candidates)
            prefix_indices[names[0]] = group_index
            group_prefixes.append(names[0])
            candidates.append(List[Int](length=3, fill=-1))
        var key = String(channel.pixel_type.value) + names[1]
        var sensitive = exact.get(key, (-1, 0))
        var insensitive = folded.get(_dwa_lower(key), (-1, 0))
        var last = max(sensitive[0], insensitive[0])
        var scheme = _DWA_UNKNOWN if last < 0 else rules[last].scheme
        var mask = sensitive[1] | insensitive[1]
        for component in range(3):
            if mask & (1 << component) != 0:
                candidates[group_index][component] = channel_index
        schemes.append(scheme)
        offsets.append(per)
        var wide = sample_bytes(channel.pixel_type)
        per += wide
        if scheme == _DWA_DCT:
            dct_channels += 1
        elif scheme == _DWA_RLE:
            rle_expected += width * lines * wide
        else:
            unknown_expected += width * lines * wide
    if unknown_size != unknown_expected or rle_raw != rle_expected:
        raise Error("EXR: DWA channel sizes do not match their rules")
    var dc_expected = ((width + 7) // 8) * ((lines + 7) // 8) * dct_channels
    # At least one AC token and at most 63 tokens per DCT block.
    var max_coefficients = _MAX_EXR_STREAM_BYTES // 8
    var ac_count = _dwa_counter(
        bytes, start + 64, min(dc_expected * 63, max_coefficients)
    )
    var dc_count = _dwa_counter(
        bytes, start + 72, min(dc_expected, max_coefficients)
    )
    if dc_count != dc_expected or ac_count < dc_expected:
        raise Error("EXR: DWA coefficient counts do not match their channels")
    if rle_size > rle_raw * 2:
        raise Error("EXR: DWA RLE data exceeds its channel layout")
    var unknown = _inflate_exact(
        bytes, starts[0], unknown_compressed, unknown_size
    )
    var ac = List[Int]()
    if ac_mode == _DWA_HUFFMAN and ac_compressed > 0:
        ac = huffman_decode(bytes, starts[1], ac_compressed, ac_count)
    else:
        var packed = _inflate_exact(
            bytes, starts[1], ac_compressed, ac_count * 2
        )
        for i in range(ac_count):
            ac.append(_u16(packed, i * 2))
    if len(ac) != ac_count:
        raise Error("EXR: DWA AC data has the wrong length")
    var dc_bytes = _reorder(
        _inflate_exact(bytes, starts[2], dc_compressed, dc_count * 2)
    )
    var dc = List[Int](capacity=dc_count)
    for i in range(dc_count):
        dc.append(_u16(dc_bytes, i * 2))
    var rle_bytes = _inflate_exact(bytes, starts[3], rle_compressed, rle_size)
    var rle = run_length_decode(rle_bytes, 0, len(rle_bytes), rle_raw)
    if len(rle) != rle_raw:
        raise Error("EXR: DWA RLE data has the wrong length")
    var out = List[UInt8](length=expected, fill=0)
    var decoded = List[Bool](length=len(channels), fill=False)
    # OpenEXR's ordered prefix map encodes complete RGB layers first.
    _sort_dwa_prefixes(group_prefixes)
    var ac_at = 0
    var dc_at = 0
    for prefix in group_prefixes:
        var group = candidates[prefix_indices[prefix]].copy()
        if group[0] >= 0 and group[1] >= 0 and group[2] >= 0:
            if (
                group[0] == group[1]
                or group[0] == group[2]
                or group[1] == group[2]
            ):
                raise Error("EXR: a DWA color group repeats a channel")
            for channel in group:
                if schemes[channel] != _DWA_DCT:
                    raise Error("EXR: DWA color groups must use DCT")
            _dwa_group(
                out,
                ac,
                dc,
                ac_at,
                dc_at,
                group,
                channels,
                offsets,
                width,
                lines,
                per,
            )
            for channel in group:
                decoded[channel] = True
    var unknown_at = 0
    var rle_at = 0
    for channel in range(len(channels)):
        if decoded[channel]:
            continue
        if schemes[channel] == _DWA_DCT:
            _dwa_group(
                out,
                ac,
                dc,
                ac_at,
                dc_at,
                [channel],
                channels,
                offsets,
                width,
                lines,
                per,
            )
            continue
        var wide = sample_bytes(channels[channel].pixel_type)
        for y in range(lines):
            for x in range(width):
                for byte in range(wide):
                    var dest = (
                        y * width * per
                        + offsets[channel] * width
                        + x * wide
                        + byte
                    )
                    if schemes[channel] == _DWA_RLE:
                        out[dest] = rle[
                            rle_at + byte * width * lines + y * width + x
                        ]
                    else:
                        out[dest] = unknown[
                            unknown_at + (y * width + x) * wide + byte
                        ]
        if schemes[channel] == _DWA_RLE:
            rle_at += width * lines * wide
        else:
            unknown_at += width * lines * wide
    if ac_at != len(ac) or dc_at != len(dc):
        raise Error("EXR: DWA coefficient streams have trailing values")
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
    if header.compression == PXR24_COMPRESSION:
        return _pxr24_decode(
            bytes, start, size, header.width(), lines, header.channels
        )
    if (
        header.compression == B44_COMPRESSION
        or header.compression == B44A_COMPRESSION
    ):
        return _b44_decode(
            bytes, start, size, header.width(), lines, header.channels
        )
    if (
        header.compression == DWAA_COMPRESSION
        or header.compression == DWAB_COMPRESSION
    ):
        return _dwa_decode(
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
    var per_block = lines_per_block(header.compression)
    var blocks = (height + per_block - 1) // per_block
    var at = header.start + 8 * blocks
    _need(len(bytes), header.start, 8 * blocks)
    # Validate every chunk's framing and line coverage before image storage.
    # The file can store chunks in either order, but each strip occurs once.
    var probe = at
    var seen = List[Bool](length=blocks, fill=False)
    for _ in range(blocks):
        _need(len(bytes), probe, 8)
        var first = _i32(bytes, probe) - header.y_min
        var count = _u32(bytes, probe + 4)
        if first < 0 or first >= height:
            raise Error("EXR: a block names a line outside the image")
        if first % per_block != 0 or seen[first // per_block]:
            raise Error("EXR: overlapping or misaligned scanline blocks")
        seen[first // per_block] = True
        var expected = _block_bytes(
            width, min(per_block, height - first), channels
        )
        if count > expected:
            raise Error("EXR: a block is larger than its scanlines")
        _need(len(bytes), probe + 8, count)
        probe += 8 + count
    var pixels = List[Float32](length=width * height * 4, fill=fill)
    for _ in range(blocks):  # pragma: no branch
        _need(len(bytes), at, 8)
        var line = _i32(bytes, at) - header.y_min
        var size = _u32(bytes, at + 4)
        at += 8
        if line < 0 or line >= height:
            raise Error("EXR: a block names a line outside the image")
        var lines = min(per_block, height - line)
        var expected = _block_bytes(width, lines, channels)
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
