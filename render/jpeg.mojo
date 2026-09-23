# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""A JPEG decoder with no image library, beside the PNG reader.

The half of three.js's `TextureLoader` that a browser does for it: a
JPEG file in, RGBA samples out, as `render.png.decode` reads a PNG. It
reads what JPEG calls *baseline* -- sequential, Huffman-coded, eight bits
a sample -- which is what a camera, a paint program and PIL write unless
asked for something else, and *progressive*, which is what a web page's
encoder writes so a picture sharpens as it loads.

**Progressive coding sends the same coefficients in pieces.** A scan
carries a band of the zigzag order -- the DC coefficient alone, or a run
of AC coefficients of one component -- and a first scan carries only the
high bits of each, the rest following one bit a scan in refinement
scans: the standard's G.1.2, spectral selection and successive
approximation. An AC scan also codes runs of empty blocks, end-of-band
runs, rather than one end-of-block code each. The coefficients are
gathered across every scan and transformed once at the end, and a
sequential file goes through the same store with one scan, so a
progressive file decodes to exactly what its baseline twin does when the
two were quantized alike.

**What a JPEG holds.** Each component -- one for gray, three for luma and
two chroma -- is cut into eight-by-eight blocks, each block is turned
into sixty-four cosine coefficients, the coefficients are divided by a
quantization table and the survivors are Huffman coded in a zigzag
order, low frequencies first. Decoding is that in reverse: Huffman
codes to coefficients, coefficients times the table, an inverse cosine
transform to samples, and the samples of the three components joined
into a color, each known by its id: JFIF numbers the luma one and the
two chroma two and three, in whatever order the frame lists them. A
chroma component is often stored at half the size of the luma, and is
read back through a triangle filter, the reconstruction libjpeg calls
fancy upsampling: the luma sample nearer a chroma sample takes three
quarters of it and a quarter of the next. The standard leaves the
filter to the decoder, and this one follows libjpeg so the two agree.

**The inverse transform is the separable float one**, the definition
rather than a fast integer approximation, rounded once at the end. A
decoder is allowed that much latitude by the standard, and it is why
two decoders agree on a JPEG to within a level or two and never to the
bit. `tests/test_jpeg.mojo` compares against libjpeg's output with that
tolerance.

**Structure is checked, as the PNG reader checks it.** A marker segment
must fit in the file, a frame header must come once and before the
scans, every table a scan names must have been defined and hold no zero,
a scan must name components the frame has, every coefficient's bits
must arrive in order and once, every component must be in some scan,
the restart markers must arrive in order, and the file must end with its
end marker. A file that asks for arithmetic coding, twelve bits a
sample, sixteen-bit quantization tables, four components, a sampling
factor past two, or three components not numbered as JFIF numbers them
is refused by name rather than mis-decoded.

JPEG carries no color space of its own. What every viewer assumes is
sRGB, and so does this: a decoded JPEG is `SRGB`.
"""

from render.framebuffer import Color
from render.png import MAX_PIXELS, DecodedImage
from render.srgb import SRGB
from std.math import cos, floor, pi, sqrt

# The markers this decoder reads, each the byte after 0xFF.
comptime SOI = UInt8(0xD8)
comptime EOI = UInt8(0xD9)
comptime SOS = UInt8(0xDA)
comptime DQT = UInt8(0xDB)
comptime DHT = UInt8(0xC4)
comptime DRI = UInt8(0xDD)
# Baseline sequential DCT, and extended sequential DCT with Huffman coding,
# which is baseline with a twelve-bit option this decoder refuses.
comptime SOF0 = UInt8(0xC0)
comptime SOF1 = UInt8(0xC1)
# Progressive DCT with Huffman coding.
comptime SOF2 = UInt8(0xC2)
# The first and last of the eight restart markers, RST0 through RST7.
comptime RST0 = UInt8(0xD0)
comptime RST7 = UInt8(0xD7)
# The application and comment segments, skipped whole.
comptime APP0 = UInt8(0xE0)
comptime APP15 = UInt8(0xEF)
comptime COM = UInt8(0xFE)
# What every JPEG marker begins with.
comptime MARKER = UInt8(0xFF)
# How many samples a block has on a side, and in all.
comptime BLOCK = 8
comptime BLOCK_SAMPLES = 64
# How many quantization and Huffman tables a file can define: four each,
# by a two-bit id.
comptime TABLE_COUNT = 4
# The most components a frame can hold here: gray, or luma and two chroma.
comptime MAX_COMPONENTS = 3
# The ids a three-component frame gives its luma, its blue difference and
# its red difference: JFIF's, which every YCbCr encoder writes. A frame
# with any other three ids is refused rather than read by position.
comptime LUMA_ID = 1
comptime BLUE_DIFFERENCE_ID = 2
comptime RED_DIFFERENCE_ID = 3
# The largest sampling factor a component can have. JPEG allows up to
# four; this decoder reads one and two, which are 4:4:4, 4:2:2 and 4:2:0,
# and refuses the rest by name.
comptime MAX_SAMPLING = 2
# Half the sample range: what a level-shifted sample is moved back by.
comptime LEVEL_SHIFT = Float32(128)
# The zigzag index of a block's last coefficient.
comptime LAST_COEFFICIENT = 63
# The lowest bit a progressive scan can start a coefficient at: the
# standard's limit on the successive approximation `Al`.
comptime MAX_APPROXIMATION = 13
# What a component's coefficient bits read before any scan has sent one.
comptime NOT_SENT = -1


def zigzag_order() -> List[Int]:
    """Return where each coefficient in a block's zigzag sequence lands in
    the block, row-major: the standard's Figure A.6.

    Returns:
        Sixty-four block positions, one per zigzag index.
    """
    return [
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


def cosine_table() -> List[Float32]:
    """Return the scaled cosines the inverse transform sums: for each
    sample position `x` and frequency `u`, `c(u) * cos((2x + 1) u pi / 16)`
    with `c(0)` of `1 / sqrt(2)` and one otherwise, halved so the row and
    column passes together divide by four.

    Returns:
        Sixty-four factors, `x * 8 + u`.
    """
    var table = List[Float32]()
    for x in range(BLOCK):  # pragma: no branch
        for u in range(BLOCK):  # pragma: no branch
            var scale = Float32(0.5)
            if u == 0:
                scale = Float32(0.5) / sqrt(Float32(2))
            table.append(
                scale
                * Float32(cos(Float64(2 * x + 1) * Float64(u) * pi / 16.0))
            )
    return table^


def inverse_dct(
    coefficients: List[Float32], cosines: List[Float32]
) -> List[Float32]:
    """Return a block's samples from its dequantized coefficients: the
    separable inverse discrete cosine transform, the standard's A.3.3.

    Rows first, then columns, each a sum of eight products with the
    factors `cosine_table` holds. The result is level-shifted back by
    `LEVEL_SHIFT`, and not yet rounded or clamped.

    Args:
        coefficients: Sixty-four dequantized coefficients, row-major.
        cosines: What `cosine_table` returns.

    Returns:
        Sixty-four samples, row-major, unrounded.
    """
    var rows = List[Float32](length=BLOCK_SAMPLES, fill=0)
    for v in range(BLOCK):  # pragma: no branch
        for x in range(BLOCK):  # pragma: no branch
            var total = Float32(0)
            for u in range(BLOCK):  # pragma: no branch
                total += cosines[x * BLOCK + u] * coefficients[v * BLOCK + u]
            rows[v * BLOCK + x] = total
    var samples = List[Float32](length=BLOCK_SAMPLES, fill=0)
    for y in range(BLOCK):  # pragma: no branch
        for x in range(BLOCK):  # pragma: no branch
            var total = Float32(0)
            for v in range(BLOCK):  # pragma: no branch
                total += cosines[y * BLOCK + v] * rows[v * BLOCK + x]
            samples[y * BLOCK + x] = total + LEVEL_SHIFT
    return samples^


def clamp_sample(value: Float32) -> UInt8:
    """Return a sample rounded to the nearest byte and held to the range.

    Args:
        value: The unrounded sample.

    Returns:
        The byte.
    """
    var rounded = Int(floor(value + 0.5))
    if rounded < 0:
        return 0
    if rounded > 255:
        return 255
    return UInt8(rounded)


def ycbcr_to_rgb(y: UInt8, cb: UInt8, cr: UInt8) -> Color:
    """Return the color three JPEG samples encode: JFIF's YCbCr to RGB,
    the standard's inverse of the ITU-R BT.601 transform.

    Args:
        y: The luma sample.
        cb: The blue-difference chroma sample.
        cr: The red-difference chroma sample.

    Returns:
        The opaque color, each channel rounded and clamped.
    """
    var luma = Float32(Int(y))
    var blue_difference = Float32(Int(cb)) - 128
    var red_difference = Float32(Int(cr)) - 128
    return Color(
        clamp_sample(luma + 1.402 * red_difference),
        clamp_sample(
            luma - 0.344136 * blue_difference - 0.714136 * red_difference
        ),
        clamp_sample(luma + 1.772 * blue_difference),
        255,
    )


def _weighted(
    plane: List[UInt8], stride: Int, width: Int, height: Int, x: Int, y: Int
) -> Float32:
    """Return the sample at (x, y) of a plane, every edge repeated.

    The edges are the component's own samples, not the whole blocks that
    hold them: the samples past them are an encoder's padding, which
    libjpeg never reads, and which a lossy block can leave far from the
    edge it copied."""
    var column = x
    if column < 0:
        column = 0
    if column >= width:
        column = width - 1
    var row = y
    if row < 0:
        row = 0
    if row >= height:
        row = height - 1
    return Float32(Int(plane[row * stride + column]))


def upsampled(
    plane: List[UInt8],
    stride: Int,
    width: Int,
    height: Int,
    x: Int,
    y: Int,
    across: Int,
    down: Int,
) -> UInt8:
    """Return a component's sample under an image pixel, interpolated
    when the component is stored at a lower resolution: the triangle
    filter libjpeg calls fancy upsampling, and the standard's own advice.

    A chroma sample sampled at half the luma's rate sits between two
    luma samples, so the luma pixel nearer it takes three quarters of
    it and one quarter of its neighbor, each way. A component at full
    resolution is read as it is. The edges repeat the component's last
    real sample, as libjpeg's do.

    Args:
        plane: The component's samples, row-major, in whole blocks.
        stride: How many samples a row of the plane holds.
        width: How many of them are the component's own: the image's
            width over `across`, rounded up.
        height: How many rows are its own, likewise.
        x: The image pixel's column.
        y: Its row.
        across: How many pixels one sample covers across, one or two.
        down: How many it covers down, one or two.

    Returns:
        The sample, rounded.
    """
    if across == 1 and down == 1:
        return plane[y * stride + x]
    # Where the pixel's center lands among the samples, each way: the
    # sample centers sit at half-integers of the coarser grid.
    var fx = (Float32(x) + 0.5) / Float32(across) - 0.5
    var fy = (Float32(y) + 0.5) / Float32(down) - 0.5
    var left = Int(floor(fx))
    var top = Int(floor(fy))
    var tx = fx - Float32(left)
    var ty = fy - Float32(top)
    var above = (
        _weighted(plane, stride, width, height, left, top) * (1 - tx)
        + _weighted(plane, stride, width, height, left + 1, top) * tx
    )
    var below = (
        _weighted(plane, stride, width, height, left, top + 1) * (1 - tx)
        + _weighted(plane, stride, width, height, left + 1, top + 1) * tx
    )
    return clamp_sample(above * (1 - ty) + below * ty)


def receive_extend(bits: Int, size: Int) -> Int:
    """Return the signed coefficient `size` raw bits encode: the standard's
    `EXTEND`, where a leading zero bit means a negative number.

    Args:
        bits: The raw bits, as an unsigned number.
        size: How many bits there are, one through sixteen.

    Returns:
        The coefficient.
    """
    if bits < (1 << (size - 1)):
        return bits - (1 << size) + 1
    return bits


struct HuffmanTable(Movable):
    """One Huffman table as a JPEG defines it: how many codes there are of
    each length, and the symbols they stand for in code order.

    Decoding walks the lengths, the standard's F.2.2.3: the code grows a
    bit at a time, and at each length the codes of that length are one
    contiguous range, so a code at most `max_code` of its length names a
    symbol at `first_symbol` plus its distance from `min_code`.
    """

    # The symbol each code stands for, in order of the codes.
    var symbols: List[UInt8]
    # Per code length one through sixteen, at that index: the smallest
    # and largest code of that length, and where its first symbol is.
    # A length with no codes has a `max_code` of -1.
    var min_code: List[Int]
    var max_code: List[Int]
    var first_symbol: List[Int]
    # Whether the table was defined at all; a scan naming an undefined
    # table is refused.
    var defined: Bool

    def __init__(out self):
        """Start undefined."""
        self.symbols = List[UInt8]()
        self.min_code = List[Int](length=17, fill=0)
        self.max_code = List[Int](length=17, fill=-1)
        self.first_symbol = List[Int](length=17, fill=0)
        self.defined = False

    def __init__(out self, counts: List[Int], var symbols: List[UInt8]) raises:
        """Build a table from its sixteen counts and its symbols.

        Args:
            counts: How many codes there are of each length, one through
                sixteen.
            symbols: The symbols in code order, as many as the counts sum to.

        Raises:
            Error: If there are not sixteen counts, the symbols do not match
                their sum, or the counts describe more codes of some length
                than that length can hold.
        """
        if len(counts) != 16:
            raise Error("A Huffman table holds sixteen code counts")
        var total = 0
        for length in range(16):  # pragma: no branch
            total += counts[length]
        if total != len(symbols):
            raise Error("A Huffman table's symbols must match its counts")
        self.symbols = symbols^
        self.min_code = List[Int](length=17, fill=0)
        self.max_code = List[Int](length=17, fill=-1)
        self.first_symbol = List[Int](length=17, fill=0)
        var code = 0
        var symbol = 0
        for length in range(1, 17):  # pragma: no branch
            var count = counts[length - 1]
            if count > 0:
                self.min_code[length] = code
                self.first_symbol[length] = symbol
                code += count
                symbol += count
                self.max_code[length] = code - 1
                # More codes than the length can hold: a table an encoder
                # cannot have written, which would otherwise decode to
                # symbols past the end.
                if code > (1 << length):
                    raise Error("A Huffman table is over-subscribed")
            code <<= 1
        self.defined = True


struct BitReader(Movable):
    """The entropy-coded bits of a scan, read one at a time.

    A 0xFF byte in the scan is followed by a stuffed zero, which is
    dropped here, and a 0xFF followed by anything else is a marker, where
    the coded data stops. Reading past a marker is an error rather than
    zeros: a scan that runs out of bits before its last block is a
    truncated file, and a decoder that pads it with zeros produces a
    plausible wrong image.
    """

    var bytes: List[UInt8]
    # Where the next byte is read from.
    var at: Int
    # The bits read and not yet handed out, and how many there are.
    var held: Int
    var count: Int

    def __init__(out self, var bytes: List[UInt8], start: Int):
        """Start reading `bytes` at `start`."""
        self.bytes = bytes^
        self.at = start
        self.held = 0
        self.count = 0

    def bit(mut self) raises -> Int:
        """Return the next bit.

        Raises:
            Error: If the scan's data ended before the bit.
        """
        if self.count == 0:
            if self.at >= len(self.bytes):
                raise Error("A scan ended before its last block")
            var byte = self.bytes[self.at]
            self.at += 1
            if byte == MARKER:
                # A stuffed zero follows a data byte of 0xFF; anything else
                # is a marker, and the coded data stopped one byte back.
                if self.at >= len(self.bytes) or self.bytes[self.at] != 0:
                    raise Error("A scan ended before its last block")
                self.at += 1
            self.held = Int(byte)
            self.count = 8
        self.count -= 1
        return (self.held >> self.count) & 1

    def bits(mut self, size: Int) raises -> Int:
        """Return the next `size` bits as an unsigned number.

        Args:
            size: How many bits, zero through sixteen.

        Returns:
            The bits, first bit most significant.

        Raises:
            Error: If the scan's data ended before the bits.
        """
        var value = 0
        for _ in range(size):  # pragma: no branch
            value = (value << 1) | self.bit()
        return value

    def decode(mut self, table: HuffmanTable) raises -> UInt8:
        """Return the next symbol under `table`.

        Args:
            table: The table the symbol is coded with.

        Returns:
            The symbol.

        Raises:
            Error: If sixteen bits make no code in the table, or the scan's
                data ended.
        """
        var code = 0
        for length in range(1, 17):  # pragma: no branch
            code = (code << 1) | self.bit()
            if code <= table.max_code[length]:
                return table.symbols[
                    table.first_symbol[length] + code - table.min_code[length]
                ]
        raise Error("A scan holds a code its Huffman table does not define")

    def restart(mut self, expected: UInt8) raises:
        """Consume a restart marker and the bits before it.

        The bits left in the current byte are padding, and the marker
        follows. Asked once per restart interval, with the marker that
        interval ends with, RST0 through RST7 in turn.

        Args:
            expected: The marker that must come next.

        Raises:
            Error: If the marker is not there, or is another one.
        """
        self.count = 0
        if self.at + 1 >= len(self.bytes) or self.bytes[self.at] != MARKER:
            raise Error("A restart interval ended without its marker")
        if self.bytes[self.at + 1] != expected:
            raise Error("A restart marker arrived out of order")
        self.at += 2

    def end(mut self) raises -> Int:
        """Return where the scan's data ends: the offset of the marker
        after it, with the bits left in the current byte discarded.

        Raises:
            Error: If no marker follows the data.
        """
        self.count = 0
        if self.at + 1 >= len(self.bytes) or self.bytes[self.at] != MARKER:
            raise Error("A scan ended without a marker after it")
        return self.at


@fieldwise_init
struct Component(Copyable, Movable):
    """One component of a frame: its id, how densely it is sampled, and
    which tables decode it.

    A component's samples are held at its own resolution, in whole
    blocks: a chroma component sampled at half the luma's holds a quarter
    as many, and is read through the triangle filter when the colors are
    joined. Its coefficients are gathered first, across every scan that
    carries them, and turned into samples once the file has ended.
    """

    var id: Int
    # Horizontal and vertical sampling factors, one or two.
    var h: Int
    var v: Int
    var quant_table: Int
    var dc_table: Int
    var ac_table: Int
    # How many blocks the component holds each way, rounded up to whole
    # minimum coded units.
    var blocks_wide: Int
    var blocks_tall: Int
    # The samples, row-major, `blocks_wide * 8` to a row.
    var samples: List[UInt8]
    # The DC coefficient the next block's is predicted from.
    var predictor: Int
    # The quantized coefficients, sixty-four a block in zigzag order, the
    # blocks row-major.
    var coefficients: List[Int32]
    # Per zigzag index, the lowest bit a scan has sent so far, or
    # `NOT_SENT`: the standard's G.1.1.1.1, and what orders the scans.
    var coefficient_bits: List[Int]
    # The quantization table in zigzag order, fixed when the component's
    # first scan begins as the standard's B.2.4.1 fixes it; empty until then.
    var quant: List[Int]


def _be16(bytes: List[UInt8], at: Int) raises -> Int:
    """Return the big-endian sixteen-bit number at `at`.

    Raises:
        Error: If the bytes are not there.
    """
    if at + 1 >= len(bytes):
        raise Error("A JPEG file ended inside a marker segment")
    return (Int(bytes[at]) << 8) | Int(bytes[at + 1])


def _read_quant_tables(
    bytes: List[UInt8],
    start: Int,
    end: Int,
    mut tables: List[List[Int]],
    mut defined: List[Bool],
) raises:
    """Read the tables a DQT segment defines, in zigzag order as stored.

    Args:
        bytes: The file.
        start: The first byte after the segment's length.
        end: The first byte after the segment.
        tables: The four tables, filled in place.
        defined: Which of the four have been defined, marked in place.

    Raises:
        Error: If a table is sixteen-bit, has an id past three, holds a
            zero, or does not fit in the segment.
    """
    var at = start
    while at < end:
        var precision = Int(bytes[at]) >> 4
        var id = Int(bytes[at]) & 15
        if precision != 0:
            raise Error(
                "A sixteen-bit quantization table is not supported: this"
                " decoder reads baseline JPEG"
            )
        if id >= TABLE_COUNT:
            raise Error("A quantization table id must be zero through three")
        if at + 1 + BLOCK_SAMPLES > end:
            raise Error("A quantization table does not fit its segment")
        var table = List[Int]()
        for index in range(BLOCK_SAMPLES):  # pragma: no branch
            var step = Int(bytes[at + 1 + index])
            # A step of zero is not a quantization: it would turn every
            # coefficient it scales to nothing and make a plausible wrong
            # image, where the standard allows no such step.
            if step == 0:
                raise Error("A quantization table holds no zero")
            table.append(step)
        tables[id] = table^
        defined[id] = True
        at += 1 + BLOCK_SAMPLES


def _read_huffman_tables(
    bytes: List[UInt8],
    start: Int,
    end: Int,
    mut dc: List[HuffmanTable],
    mut ac: List[HuffmanTable],
) raises:
    """Read the tables a DHT segment defines.

    Args:
        bytes: The file.
        start: The first byte after the segment's length.
        end: The first byte after the segment.
        dc: The four DC tables, filled in place.
        ac: The four AC tables, filled in place.

    Raises:
        Error: If a table's class is not zero or one, its id is past three,
            it does not fit in the segment, or `HuffmanTable` refuses it.
    """
    var at = start
    while at < end:
        var kind = Int(bytes[at]) >> 4
        var id = Int(bytes[at]) & 15
        if kind > 1:
            raise Error("A Huffman table's class must be zero or one")
        if id >= TABLE_COUNT:
            raise Error("A Huffman table id must be zero through three")
        if at + 17 > end:
            raise Error("A Huffman table does not fit its segment")
        var counts = List[Int]()
        var total = 0
        for index in range(16):  # pragma: no branch
            counts.append(Int(bytes[at + 1 + index]))
            total += counts[index]
        if at + 17 + total > end:
            raise Error("A Huffman table does not fit its segment")
        var symbols = List[UInt8]()
        for index in range(total):
            symbols.append(bytes[at + 17 + index])
        if kind == 0:
            dc[id] = HuffmanTable(counts, symbols^)
        else:
            ac[id] = HuffmanTable(counts, symbols^)
        at += 17 + total


def _read_frame(
    bytes: List[UInt8],
    start: Int,
    end: Int,
    mut width: Int,
    mut height: Int,
    mut components: List[Component],
) raises:
    """Read a frame header: the image size and its components.

    Args:
        bytes: The file.
        start: The first byte after the segment's length.
        end: The first byte after the segment.
        width: Set to the image's width.
        height: Set to its height.
        components: Filled with its components, with their sample planes
            not yet sized.

    Raises:
        Error: If the precision is not eight bits, a dimension is zero or
            past what this decoder builds, the component count is neither
            one nor three, a sampling factor is zero or past two, a
            quantization table id is past three, two components share an
            id, or the segment is the wrong size.
    """
    if start + 6 > end:
        raise Error("A frame header is too short")
    if bytes[start] != 8:
        raise Error(
            "Only eight bits a sample are supported: this decoder reads"
            " baseline JPEG"
        )
    height = _be16(bytes, start + 1)
    width = _be16(bytes, start + 3)
    if width == 0 or height == 0:
        raise Error("A JPEG file must have a width and a height")
    # Sixteen bits a dimension, so no dimension can pass the PNG reader's
    # `MAX_DIMENSION`; the product can pass its `MAX_PIXELS`.
    if width * height > MAX_PIXELS:
        raise Error("Image has too many pixels")
    var count = Int(bytes[start + 5])
    if count != 1 and count != MAX_COMPONENTS:
        raise Error(
            "Only a gray or a three-component JPEG is supported: a"
            " four-component file is CMYK, which this decoder does not read"
        )
    if start + 6 + count * 3 != end:
        raise Error("A frame header's length does not match its components")
    for index in range(count):  # pragma: no branch
        var at = start + 6 + index * 3
        var id = Int(bytes[at])
        var h = Int(bytes[at + 1]) >> 4
        var v = Int(bytes[at + 1]) & 15
        var table = Int(bytes[at + 2])
        if h == 0 or v == 0 or h > MAX_SAMPLING or v > MAX_SAMPLING:
            raise Error("A sampling factor must be one or two")
        if table >= TABLE_COUNT:
            raise Error("A quantization table id must be zero through three")
        for earlier in range(len(components)):
            if components[earlier].id == id:
                raise Error("Two components share one id")
        components.append(
            Component(
                id,
                h,
                v,
                table,
                0,
                0,
                0,
                0,
                List[UInt8](),
                0,
                List[Int32](),
                List[Int](length=BLOCK_SAMPLES, fill=NOT_SENT),
                List[Int](),
            )
        )
    # Three components are luma and two chroma by their ids, not by their
    # order in the frame: JFIF numbers them one, two and three, and a
    # frame numbered any other way -- Adobe's RGB, say -- is something this
    # decoder cannot turn into a color and says so.
    if count == MAX_COMPONENTS:
        var wanted: List[Int] = [LUMA_ID, BLUE_DIFFERENCE_ID, RED_DIFFERENCE_ID]
        for index in range(len(wanted)):  # pragma: no branch
            if _slot_of(components, wanted[index]) < 0:
                raise Error(
                    "A three-component JPEG must number its components one,"
                    " two and three, luma first, as JFIF does: no other"
                    " numbering names a YCbCr file this decoder can read"
                )


def _slot_of(components: List[Component], id: Int) -> Int:
    """Return which component has `id`, or -1 for none."""
    for slot in range(len(components)):  # pragma: no branch
        if components[slot].id == id:
            return slot
    return -1


@fieldwise_init
struct Scan(Movable):
    """A scan header: which components it holds, in the order their
    blocks arrive, and which coefficients and bits of them it carries."""

    var order: List[Int]
    # The band of zigzag indices it carries, `Ss` through `Se`.
    var spectral_start: Int
    var spectral_end: Int
    # The bit the last scan of this band stopped at, `Ah`, zero for a
    # first scan; and the bit this one stops at, `Al`.
    var high_bit: Int
    var low_bit: Int


def _read_scan(
    bytes: List[UInt8],
    start: Int,
    end: Int,
    progressive: Bool,
    mut components: List[Component],
    quant_tables: List[List[Int]],
    quant_defined: List[Bool],
    dc_tables: List[HuffmanTable],
    ac_tables: List[HuffmanTable],
) raises -> Scan:
    """Read a scan header, assigning each component its Huffman tables and
    marking the coefficient bits the scan sends.

    Args:
        bytes: The file.
        start: The first byte after the segment's length.
        end: The first byte after the segment.
        progressive: Whether the frame is progressive.
        components: The frame's components, given their tables in place.
        quant_tables: The four quantization tables.
        quant_defined: Which of them have been defined.
        dc_tables: The four DC Huffman tables.
        ac_tables: The four AC Huffman tables.

    Returns:
        The scan.

    Raises:
        Error: If the scan names no component, more than the frame has,
            one the frame lacks or one twice, names a Huffman table id
            past three or a table not defined, asks for a band or bits
            the frame's coding does not allow, or sends a coefficient's
            bits out of order or twice.
    """
    if start >= end:
        raise Error("A scan header is too short")
    var count = Int(bytes[start])
    if count == 0 or count > len(components):
        raise Error("A scan must name one to all of the frame's components")
    if start + 1 + count * 2 + 3 != end:
        raise Error("A scan header's length does not match its components")
    var order = List[Int]()
    for index in range(count):  # pragma: no branch
        var at = start + 1 + index * 2
        var id = Int(bytes[at])
        var dc = Int(bytes[at + 1]) >> 4
        var ac = Int(bytes[at + 1]) & 15
        if dc >= TABLE_COUNT or ac >= TABLE_COUNT:
            raise Error("A Huffman table id must be zero through three")
        var slot = _slot_of(components, id)
        if slot < 0:
            raise Error("A scan names a component the frame does not have")
        for earlier in range(len(order)):
            if order[earlier] == slot:
                raise Error("A scan names one component twice")
        components[slot].dc_table = dc
        components[slot].ac_table = ac
        order.append(slot)
    var tail = start + 1 + count * 2
    var first = Int(bytes[tail])
    var last = Int(bytes[tail + 1])
    var high = Int(bytes[tail + 2]) >> 4
    var low = Int(bytes[tail + 2]) & 15
    if not progressive:
        if first != 0 or last != LAST_COEFFICIENT or high != 0 or low != 0:
            raise Error(
                "A sequential frame's scan must cover every coefficient at once"
            )
    elif first == 0:
        if last != 0:
            raise Error("A progressive DC scan holds no AC coefficient")
    else:
        if last < first or last > LAST_COEFFICIENT:
            raise Error(
                "A progressive AC scan's band must run forward and end by"
                " the sixty-third coefficient"
            )
        if count != 1:
            raise Error("A progressive AC scan holds one component")
    if low > MAX_APPROXIMATION:
        raise Error("A scan's successive approximation stops past bit 13")
    if high != 0 and low != high - 1:
        raise Error("A refinement scan adds one bit to what came before")
    # The bits every coefficient of the band must stand at: none sent for
    # a first scan, and down to `Ah` for a refinement.
    var expected = NOT_SENT
    if high > 0:
        expected = high
    for index in range(count):  # pragma: no branch
        ref component = components[order[index]]
        if not quant_defined[component.quant_table]:
            raise Error("A component names a quantization table not defined")
        # A DC refinement is raw bits, and a DC scan holds no AC codes.
        var needs_dc = first == 0 and high == 0
        if needs_dc and not dc_tables[component.dc_table].defined:
            raise Error("A component names a DC Huffman table not defined")
        if last > 0 and not ac_tables[component.ac_table].defined:
            raise Error("A component names an AC Huffman table not defined")
        if first > 0 and component.coefficient_bits[0] == NOT_SENT:
            raise Error("An AC scan arrived before its component's DC scan")
        for k in range(first, last + 1):  # pragma: no branch
            if component.coefficient_bits[k] != expected:
                raise Error(
                    "A scan sends a coefficient's bits out of order or twice"
                )
            component.coefficient_bits[k] = low
        if len(component.quant) == 0:
            component.quant = quant_tables[component.quant_table].copy()
    return Scan(order^, first, last, high, low)


def _dc_difference(mut reader: BitReader, dc: HuffmanTable) raises -> Int:
    """Return the next DC difference: a size under the DC table, then that
    many raw bits, the standard's F.2.2.1."""
    var size = Int(reader.decode(dc))
    if size > 0:
        return receive_extend(reader.bits(size), size)
    return 0


def _decode_sequential(
    mut reader: BitReader,
    mut component: Component,
    dc: HuffmanTable,
    ac: HuffmanTable,
    base: Int,
) raises:
    """Decode one sequential block's coefficients.

    The DC coefficient is a difference from the last block's, the AC
    coefficients a run of zeros and a value each, in zigzag order until
    the end-of-block symbol or the sixty-fourth: the standard's F.2.2."""
    component.predictor += _dc_difference(reader, dc)
    component.coefficients[base] = Int32(component.predictor)
    var index = 1
    while index < BLOCK_SAMPLES:
        var symbol = Int(reader.decode(ac))
        var run = symbol >> 4
        var bits = symbol & 15
        if bits == 0:
            if run != 15:
                # End of block: the rest are zero.
                break
            index += 16
            continue
        index += run
        if index >= BLOCK_SAMPLES:
            raise Error("A block's coefficients run past its end")
        component.coefficients[base + index] = Int32(
            receive_extend(reader.bits(bits), bits)
        )
        index += 1


def _decode_ac_first(
    mut reader: BitReader,
    mut component: Component,
    ac: HuffmanTable,
    base: Int,
    scan: Scan,
    mut eob_run: Int,
) raises:
    """Decode the first bits of one block's band: the standard's G.1.2.2.

    As the sequential AC coding, except that each value is scaled up past
    the bits a later scan refines, and an end-of-band code carries a
    count of the blocks after this one whose band is empty too."""
    if eob_run > 0:
        eob_run -= 1
        return
    var index = scan.spectral_start
    while index <= scan.spectral_end:
        var symbol = Int(reader.decode(ac))
        var run = symbol >> 4
        var bits = symbol & 15
        if bits == 0:
            if run != 15:
                eob_run = (1 << run) - 1 + reader.bits(run)
                return
            index += 16
            continue
        index += run
        if index > scan.spectral_end:
            raise Error("A block's coefficients run past its band")
        component.coefficients[base + index] = Int32(
            receive_extend(reader.bits(bits), bits) << scan.low_bit
        )
        index += 1


def _refine(
    mut reader: BitReader, mut component: Component, at: Int, one: Int
) raises:
    """Refine a coefficient already known to be nonzero by one bit of
    magnitude, away from zero.

    The bit is never set already: the scan order `_read_scan` checks
    leaves every coefficient a multiple of twice `one` here."""
    if reader.bit() == 1:
        var value = Int(component.coefficients[at])
        if value > 0:
            component.coefficients[at] = Int32(value + one)
        else:
            component.coefficients[at] = Int32(value - one)


def _decode_ac_refine(
    mut reader: BitReader,
    mut component: Component,
    ac: HuffmanTable,
    base: Int,
    scan: Scan,
    mut eob_run: Int,
) raises:
    """Decode one more bit of one block's band: the standard's G.1.2.3.

    A coefficient already nonzero gets a correction bit as it is passed.
    A zero one either stays zero, counted against the run, or becomes
    plus or minus the new bit; an end-of-band run leaves only the
    correction bits for the rest of this block and the next ones."""
    var one = 1 << scan.low_bit
    var index = scan.spectral_start
    if eob_run == 0:
        while index <= scan.spectral_end:
            var symbol = Int(reader.decode(ac))
            var run = symbol >> 4
            var bits = symbol & 15
            var value = 0
            if bits == 0:
                if run != 15:
                    eob_run = (1 << run) + reader.bits(run)
                    break
            else:
                if bits != 1:
                    raise Error(
                        "A refinement scan's new coefficient must be one bit"
                    )
                value = -one
                if reader.bit() == 1:
                    value = one
            # Pass `run` zero coefficients, refining the nonzero ones on
            # the way, and stop on the next zero one.
            while index <= scan.spectral_end:
                var at = base + index
                if component.coefficients[at] != 0:
                    _refine(reader, component, at, one)
                elif run == 0:
                    break
                else:
                    run -= 1
                index += 1
            if value != 0:
                if index > scan.spectral_end:
                    raise Error("A block's coefficients run past its band")
                component.coefficients[base + index] = Int32(value)
            index += 1
    if eob_run > 0:
        while index <= scan.spectral_end:
            var at = base + index
            if component.coefficients[at] != 0:
                _refine(reader, component, at, one)
            index += 1
        eob_run -= 1


def _decode_coefficients(
    mut reader: BitReader,
    mut component: Component,
    dc: HuffmanTable,
    ac: HuffmanTable,
    scan: Scan,
    progressive: Bool,
    mut eob_run: Int,
    block_x: Int,
    block_y: Int,
) raises:
    """Decode what one scan holds of one block into its coefficients."""
    var base = (block_y * component.blocks_wide + block_x) * BLOCK_SAMPLES
    if not progressive:
        _decode_sequential(reader, component, dc, ac, base)
    elif scan.spectral_start == 0:
        if scan.high_bit == 0:
            component.predictor += _dc_difference(reader, dc)
            component.coefficients[base] = Int32(
                component.predictor << scan.low_bit
            )
        elif reader.bit() == 1:
            # The DC coefficient's bits are two's complement, not a
            # magnitude: the new bit is set, whatever the sign.
            component.coefficients[base] |= Int32(1 << scan.low_bit)
    elif scan.high_bit == 0:
        _decode_ac_first(reader, component, ac, base, scan, eob_run)
    else:
        _decode_ac_refine(reader, component, ac, base, scan, eob_run)


def _decode_scan(
    mut reader: BitReader,
    scan: Scan,
    mut components: List[Component],
    dc_tables: List[HuffmanTable],
    ac_tables: List[HuffmanTable],
    progressive: Bool,
    restart_interval: Int,
    width: Int,
    height: Int,
    h_max: Int,
    v_max: Int,
) raises:
    """Decode one scan's entropy-coded data into its components'
    coefficients.

    A scan of several components is interleaved: a minimum coded unit
    holds each one's blocks by its sampling factors. A scan of one is
    not: its unit is one block, and it covers only the blocks the
    component's own samples reach, the standard's A.2.2."""
    var across = (width + BLOCK * h_max - 1) // (BLOCK * h_max)
    var down = (height + BLOCK * v_max - 1) // (BLOCK * v_max)
    var single = len(scan.order) == 1
    if single:
        ref only = components[scan.order[0]]
        var samples_wide = (width * only.h + h_max - 1) // h_max
        var samples_tall = (height * only.v + v_max - 1) // v_max
        across = (samples_wide + BLOCK - 1) // BLOCK
        down = (samples_tall + BLOCK - 1) // BLOCK
    for index in range(len(scan.order)):  # pragma: no branch
        components[scan.order[index]].predictor = 0
    var eob_run = 0
    var units_done = 0
    var next_restart = RST0
    for unit_y in range(down):  # pragma: no branch
        for unit_x in range(across):  # pragma: no branch
            if (
                restart_interval > 0
                and units_done > 0
                and units_done % restart_interval == 0
            ):
                reader.restart(next_restart)
                next_restart = RST0 + UInt8((Int(next_restart - RST0) + 1) % 8)
                eob_run = 0
                for index in range(len(scan.order)):  # pragma: no branch
                    components[scan.order[index]].predictor = 0
            # The blocks arrive in the scan's order, which need not be the
            # frame's.
            for entry in range(len(scan.order)):  # pragma: no branch
                ref component = components[scan.order[entry]]
                var wide = component.h
                var tall = component.v
                if single:
                    wide = 1
                    tall = 1
                for v in range(tall):  # pragma: no branch
                    for h in range(wide):  # pragma: no branch
                        _decode_coefficients(
                            reader,
                            component,
                            dc_tables[component.dc_table],
                            ac_tables[component.ac_table],
                            scan,
                            progressive,
                            eob_run,
                            unit_x * wide + h,
                            unit_y * tall + v,
                        )
            units_done += 1


def _lay_out(
    mut components: List[Component],
    width: Int,
    height: Int,
    mut h_max: Int,
    mut v_max: Int,
):
    """Size every component's coefficients in whole minimum coded units,
    and set the largest sampling factors each way."""
    # A gray file has one component and its unit is one block, whatever
    # its factors say; the standard's A.2.2.
    if len(components) == 1:
        components[0].h = 1
        components[0].v = 1
    h_max = 1
    v_max = 1
    for index in range(len(components)):  # pragma: no branch
        if components[index].h > h_max:
            h_max = components[index].h
        if components[index].v > v_max:
            v_max = components[index].v
    var units_wide = (width + BLOCK * h_max - 1) // (BLOCK * h_max)
    var units_tall = (height + BLOCK * v_max - 1) // (BLOCK * v_max)
    for index in range(len(components)):  # pragma: no branch
        ref component = components[index]
        component.blocks_wide = units_wide * component.h
        component.blocks_tall = units_tall * component.v
        component.coefficients = List[Int32](
            length=component.blocks_wide
            * component.blocks_tall
            * BLOCK_SAMPLES,
            fill=0,
        )


def _to_samples(
    mut component: Component, zigzag: List[Int], cosines: List[Float32]
):
    """Turn a component's coefficients into its samples: each block's
    dequantized, transformed back, rounded and clamped."""
    var stride = component.blocks_wide * BLOCK
    component.samples = List[UInt8](
        length=stride * component.blocks_tall * BLOCK, fill=0
    )
    var coefficients = List[Float32](length=BLOCK_SAMPLES, fill=0)
    for block_y in range(component.blocks_tall):  # pragma: no branch
        for block_x in range(component.blocks_wide):  # pragma: no branch
            var base = (
                block_y * component.blocks_wide + block_x
            ) * BLOCK_SAMPLES
            for index in range(BLOCK_SAMPLES):  # pragma: no branch
                coefficients[zigzag[index]] = Float32(
                    Int(component.coefficients[base + index])
                    * component.quant[index]
                )
            var samples = inverse_dct(coefficients, cosines)
            for y in range(BLOCK):  # pragma: no branch
                var row = (block_y * BLOCK + y) * stride + block_x * BLOCK
                for x in range(BLOCK):  # pragma: no branch
                    component.samples[row + x] = clamp_sample(
                        samples[y * BLOCK + x]
                    )


def decode(bytes: List[UInt8]) raises -> DecodedImage:
    """Return the image a baseline or progressive JPEG file holds, as RGBA.

    Reads a gray or a YCbCr file, sequential or progressive and Huffman
    coded at eight bits a sample, with sampling factors of one or two --
    4:4:4, 4:2:2 and 4:2:0 -- any restart interval, and scans of every
    component or of one, and widens it to opaque RGBA, since that is what
    a `Texture` holds. Everything else JPEG allows -- arithmetic coding,
    twelve bits, sixteen-bit quantization tables, larger sampling
    factors, four components, components numbered other than JFIF's one,
    two and three -- is refused by name.

    Args:
        bytes: The complete file.

    Returns:
        The image, `SRGB`, since a JPEG declares nothing else.

    Raises:
        Error: If the file does not begin with a start-of-image marker or
            end with an end-of-image marker, a marker segment does not fit,
            the frame header is missing, doubled or malformed, a table is
            malformed or missing when a scan names it, a scan header does
            not match the frame or sends bits out of order, a component is
            in no scan, the coded data ends early, holds a code no table
            defines, or arrives with a restart marker out of place, or the
            file uses a feature this decoder does not have.
    """
    if len(bytes) < 4 or bytes[0] != MARKER or bytes[1] != SOI:
        raise Error("Not a JPEG file: no start-of-image marker")
    var quant_tables = List[List[Int]]()
    var quant_defined = List[Bool]()
    var dc_tables = List[HuffmanTable]()
    var ac_tables = List[HuffmanTable]()
    for _ in range(TABLE_COUNT):  # pragma: no branch
        quant_tables.append(List[Int](length=BLOCK_SAMPLES, fill=1))
        quant_defined.append(False)
        dc_tables.append(HuffmanTable())
        ac_tables.append(HuffmanTable())
    var width = 0
    var height = 0
    var h_max = 1
    var v_max = 1
    var components = List[Component]()
    var framed = False
    var progressive = False
    var scanned = False
    var restart_interval = 0
    var reader = BitReader(bytes.copy(), 0)
    var at = 2
    var ended = False
    while not ended:
        if at + 1 >= len(bytes):
            raise Error("A JPEG file ended before its end-of-image marker")
        if bytes[at] != MARKER:
            raise Error("A JPEG marker was expected and something else found")
        var marker = bytes[at + 1]
        # A run of fill bytes before a marker is allowed.
        if marker == MARKER:
            at += 1
            continue
        if marker == EOI:
            ended = True
            continue
        if marker == SOI or (marker >= RST0 and marker <= RST7):
            raise Error("A JPEG marker arrived where a segment was expected")
        var length = _be16(bytes, at + 2)
        if length < 2 or at + 2 + length > len(bytes):
            raise Error("A JPEG marker segment does not fit in the file")
        var start = at + 4
        var end = at + 2 + length
        if marker == DQT:
            _read_quant_tables(bytes, start, end, quant_tables, quant_defined)
        elif marker == DHT:
            _read_huffman_tables(bytes, start, end, dc_tables, ac_tables)
        elif marker == DRI:
            if length != 4:
                raise Error("A restart interval segment holds one number")
            restart_interval = _be16(bytes, start)
        elif marker == SOF0 or marker == SOF1 or marker == SOF2:
            if framed:
                raise Error("A JPEG file holds one frame header")
            _read_frame(bytes, start, end, width, height, components)
            _lay_out(components, width, height, h_max, v_max)
            framed = True
            progressive = marker == SOF2
        elif marker == SOS:
            if not framed:
                raise Error("A scan arrived before the frame header")
            var scan = _read_scan(
                bytes,
                start,
                end,
                progressive,
                components,
                quant_tables,
                quant_defined,
                dc_tables,
                ac_tables,
            )
            reader.at = end
            _decode_scan(
                reader,
                scan,
                components,
                dc_tables,
                ac_tables,
                progressive,
                restart_interval,
                width,
                height,
                h_max,
                v_max,
            )
            end = reader.end()
            scanned = True
        elif (marker >= APP0 and marker <= APP15) or marker == COM:
            pass
        else:
            raise Error(
                "A JPEG marker this decoder does not read: only sequential"
                " and progressive Huffman coding are supported"
            )
        at = end
    if not scanned:
        raise Error("A JPEG file ended before its scan")
    # The end marker, and nothing after it.
    if at + 2 != len(bytes):
        raise Error("A JPEG file must end with its end-of-image marker")

    var zigzag = zigzag_order()
    var cosines = cosine_table()
    for index in range(len(components)):  # pragma: no branch
        if components[index].coefficient_bits[0] == NOT_SENT:
            raise Error("A component is in no scan")
        _to_samples(components[index], zigzag, cosines)

    # Which component is the luma and which the two chroma, by id.
    var planes = List[Int]()
    if len(components) == MAX_COMPONENTS:
        planes.append(_slot_of(components, LUMA_ID))
        planes.append(_slot_of(components, BLUE_DIFFERENCE_ID))
        planes.append(_slot_of(components, RED_DIFFERENCE_ID))
    var pixels = List[UInt8]()
    pixels.reserve(width * height * DecodedImage.CHANNELS)
    for y in range(height):  # pragma: no branch
        for x in range(width):  # pragma: no branch
            var color: Color
            if len(components) == 1:
                var gray = components[0].samples[
                    y * components[0].blocks_wide * BLOCK + x
                ]
                color = Color(gray, gray, gray, 255)
            else:
                var samples = List[UInt8]()
                for index in range(MAX_COMPONENTS):  # pragma: no branch
                    ref component = components[planes[index]]
                    var across = h_max // component.h
                    var down = v_max // component.v
                    samples.append(
                        upsampled(
                            component.samples,
                            component.blocks_wide * BLOCK,
                            (width + across - 1) // across,
                            (height + down - 1) // down,
                            x,
                            y,
                            across,
                            down,
                        )
                    )
                color = ycbcr_to_rgb(samples[0], samples[1], samples[2])
            pixels.append(color.r)
            pixels.append(color.g)
            pixels.append(color.b)
            pixels.append(color.a)
    return DecodedImage(width, height, pixels^, SRGB)
