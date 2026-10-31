# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""RGBA floats written as an OpenEXR file: three.js's `EXRExporter`, and
the other half of `render.exr`.

`export_exr` takes the texels of a `FloatType` data texture, and
`export_exr_half` takes those of a `HalfFloatType` one. Each has four
values a texel, red, green, blue and alpha, from the bottom row up, as a
three.js `DataTexture` holds them. `export_exr_image` takes a
`FloatImage`, whose rows go from the top down, so that `render.exr`
reads the file back to the same image.

The file is a scanline file with one part. Every byte is the byte that
three.js r187 writes. The header has the attributes three.js writes, in
its order. The channels are `A`, `B`, `G` and `R`, each of
`HALF_SAMPLES` or `FLOAT_SAMPLES`. A half is made with three.js's
`DataUtils.toHalfFloat`, which cuts off the extra bits and clamps to
65,504.

**The five compressions.** The blocks are stored as they are
(`NO_COMPRESSION`), or compressed one of four ways:

- `RLE_COMPRESSION`: one line a block. The bytes are split and
  predicted as for zlib, then run-length coded as OpenEXR's
  `rleCompress` codes them.
- `ZIPS_COMPRESSION` and `ZIP_COMPRESSION`: one line or sixteen lines
  a block, split, predicted and compressed with zlib. `ZIP_COMPRESSION`
  is the default. zlib is fflate's, from `render.deflate`.
- `PIZ_COMPRESSION`: thirty-two lines a block. The sixteen-bit words of
  each channel go through a table of the words that occur, a Haar
  wavelet and a Huffman code, as OpenEXR's `PizCompressor` does it.
  `render.exr.piz_decode` is the other half.

A block that its compression does not make smaller is written as raw
lines, which is how a reader takes it.

**three.js before r187.** three.js r186 and earlier wrote two kinds of
block that its own `EXRLoader` read wrong values from. It compressed the
last block of a `ZIP_COMPRESSION` file at the size of a full block, and
it wrote the zlib stream of a block that zlib did not make smaller. This
port always wrote both as OpenEXR says, and r187 writes them the same
way.

An image with no texels, or data of the wrong length, is refused.
three.js writes a file with a data window of minus one.
"""

from core.binary import (
    append_little_endian,
    append_little_endian_u16,
    append_little_endian_u32,
    copy_byte_range,
    store_little_endian,
)
from core.extent import require_positive_extent
from geometries.curve_modifier import to_half_float
from render.deflate import zlib_deflate
from render.exr import (
    A_OFFSET,
    BITMAP_SIZE,
    FLOAT_SAMPLES,
    HALF_SAMPLES,
    HUF_ENCSIZE,
    LONG_ZEROCODE_RUN,
    MAX_CODE_LENGTH,
    MOD_MASK,
    NO_COMPRESSION,
    PIZ_COMPRESSION,
    RLE_COMPRESSION,
    SHORTEST_LONG_RUN,
    SHORT_ZEROCODE_RUN,
    USHORT_RANGE,
    ZIPS_COMPRESSION,
    ZIP_COMPRESSION,
    ExrCompression,
    ExrPixelType,
    half_to_float,
    lines_per_block,
)
from render.float_image import FloatImage
from std.math import isnan
from std.memory import bitcast

# The longest run of zero code lengths one long run code holds: its eight
# bits plus the shortest long run. OpenEXR's `LONGEST_LONG_RUN`.
comptime LONGEST_LONG_RUN = 255 + SHORTEST_LONG_RUN
# The most bytes, or the most repeats after the first, one RLE count
# byte holds.
comptime MAX_RLE_RUN = 127
# The most repeats after the first that one Huffman run code holds: eight
# bits.
comptime MAX_HUFFMAN_RUN = 255


def _push_string(mut out: List[UInt8], text: String):
    """Append a string and its zero byte."""
    out.extend(text.as_bytes())
    out.append(0)


def _attribute(mut out: List[UInt8], name: String, kind: String, size: Int):
    """Append an attribute's name, type and size."""
    _push_string(out, name)
    _push_string(out, kind)
    append_little_endian_u32(out, size)


def _check(
    width: Int,
    height: Int,
    count: Int,
    compression: ExrCompression,
    type: ExrPixelType,
) raises:
    """Refuse a size, a compression or a sample type that three.js does
    not write."""
    require_positive_extent(
        width, height, "EXR export: an image needs a width and a height"
    )
    # Four channels, and four bytes a float sample. A side of 2^31 wraps
    # `width * height * 4` to zero, so an empty buffer looks complete.
    if width > (Int.MAX // 16) // height:
        raise Error("EXR export: the image is larger than this port writes")
    if count != width * height * 4:
        raise Error(
            "EXR export: the data must hold four values for each of the "
            + String(width * height)
            + " texels, not "
            + String(count)
            + " values"
        )
    if not (
        compression.is_valid() and compression.value <= PIZ_COMPRESSION.value
    ):
        raise Error(
            "EXR export: the compression must be none, RLE, ZIPS, ZIP or PIZ"
        )
    if not (type == HALF_SAMPLES or type == FLOAT_SAMPLES):
        raise Error("EXR export: the sample type must be HALF or FLOAT")


def _predicted(raw: List[UInt8], start: Int, end: Int) -> List[UInt8]:
    """Return a block's bytes split and predicted, as RLE and zlib take
    them: three.js's `reorderAndPredict`.

    The even bytes come first and the odd bytes after them. Then each
    byte but the first is stored as its difference from the one before,
    plus 128.
    """
    var n = end - start
    var tmp = List[UInt8](length=n, fill=0)
    var t1 = 0
    var t2 = (n + 1) // 2
    # A block has one line or more. The loop always runs.
    for s in range(n):  # pragma: no branch
        if s % 2 == 0:
            tmp[t1] = raw[start + s]
            t1 += 1
        else:
            tmp[t2] = raw[start + s]
            t2 += 1
    var p = Int(tmp[0])
    # A line has eight bytes or more. The loop always runs.
    for t in range(1, n):  # pragma: no branch
        var d = Int(tmp[t]) - p + 128 + 256
        p = Int(tmp[t])
        tmp[t] = UInt8(d & 255)
    return tmp^


def _starts_run(data: List[UInt8], at: Int) -> Bool:
    """Return True if three equal bytes start at `at`."""
    if at + 2 >= len(data):
        return False
    if data[at] != data[at + 1]:
        return False
    return data[at + 1] == data[at + 2]


def _run_length(data: List[UInt8]) -> List[UInt8]:
    """Return predicted bytes run-length coded: three.js's `compressRLE`,
    from OpenEXR's `rleCompress`.

    A count byte from zero to 127 is followed by one byte that repeats one
    more time than the count. A count byte from 129 to 255 is followed by
    256 less the count bytes as they stand. `render.exr.run_length_decode`
    reads it.

    three.js counts as it goes. Here `rune` starts one past `runs` each
    time, so each count is a distance, and each loop's limit is three.js's
    bound on the count.
    """
    var end = len(data)
    var out = List[UInt8](capacity=2 * end)
    var runs = 0
    var rune = 1
    while runs < end:
        # The bytes equal to the first, at most `MAX_RLE_RUN` of them.
        var limit = min(end, runs + 1 + MAX_RLE_RUN)
        while rune < limit:
            if data[runs] != data[rune]:
                break
            rune += 1
        var count = rune - runs - 1
        if count >= 2:
            out.append(UInt8(count))
            out.append(data[runs])
            runs = rune
        else:
            # Bytes as they stand, up to the next run of three.
            limit = min(end, runs + MAX_RLE_RUN)
            while rune < limit:
                if _starts_run(data, rune):
                    break
                rune += 1
            out.append(UInt8(256 - (rune - runs)))
            while runs < rune:
                out.append(data[runs])
                runs += 1
        rune += 1
    return out^


def _signed16(value: Int) -> Int:
    """Return the low sixteen bits of `value` read as a signed number."""
    return ((value & 0xFFFF) ^ 0x8000) - 0x8000


def _wavelet_pair(a: Int, b: Int, wide: Bool) -> Tuple[Int, Int]:
    """Return the average and difference one step of PIZ's wavelet makes:
    three.js's `wenc14`, or `wenc16` when `wide`.

    `render.exr.wavelet_pair` undoes it.
    """
    if wide:
        var ao = (a + A_OFFSET) & MOD_MASK
        var m = (ao + b) >> 1
        var d = ao - b
        if d < 0:
            m = (m + A_OFFSET) & MOD_MASK
        return (m, d & MOD_MASK)
    var sa = _signed16(a)
    var sb = _signed16(b)
    return (((sa + sb) >> 1) & 0xFFFF, (sa - sb) & 0xFFFF)


def _wavelet_encode(
    mut buffer: List[Int],
    j: Int,
    nx: Int,
    ox: Int,
    ny: Int,
    oy: Int,
    largest: Int,
):
    """Apply PIZ's two-dimensional Haar wavelet in place: three.js's
    `wav2Encode`, from OpenEXR.

    Each level pairs values `p` apart across and down, from one apart up
    to the largest power of two that fits the shorter side. A last column
    or row without a partner is paired in one direction only.
    `render.exr.wavelet_decode` undoes it.

    Args:
        buffer: The values, sixteen bits each.
        j: Where this channel's first value is.
        nx: How many values across.
        ox: How far apart two values across are.
        ny: How many values down.
        oy: How far apart two values down are.
        largest: The largest value the table maps to. From 16,384 up,
            the sixteen-bit form is used.
    """
    var wide = largest >= (1 << 14)
    var n = ny if nx > ny else nx
    var p = 1
    var p2 = 2
    while p2 <= n:
        var py = j
        var ey = j + oy * (ny - p2)
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
                var top = _wavelet_pair(buffer[px], buffer[p01], wide)
                var bottom = _wavelet_pair(buffer[p10], buffer[p11], wide)
                var low = _wavelet_pair(top[0], bottom[0], wide)
                buffer[px] = low[0]
                buffer[p10] = low[1]
                var high = _wavelet_pair(top[1], bottom[1], wide)
                buffer[p01] = high[0]
                buffer[p11] = high[1]
                px += ox2
            if nx & p != 0:
                var p10 = px + oy1
                var pair = _wavelet_pair(buffer[px], buffer[p10], wide)
                buffer[px] = pair[0]
                buffer[p10] = pair[1]
            py += oy2
        if ny & p != 0:
            var px = py
            var ex = py + ox * (nx - p2)
            while px <= ex:
                var p01 = px + ox1
                var pair = _wavelet_pair(buffer[px], buffer[p01], wide)
                buffer[px] = pair[0]
                buffer[p01] = pair[1]
                px += ox2
        p = p2
        p2 <<= 1


struct _BitWriter(Movable):
    """Bits written most significant first into bytes: three.js's
    `outputBits` and its writer, with a list that grows instead of a
    buffer that can overflow."""

    var out: List[UInt8]
    # The bits not yet in a byte, and how many there are: fewer than
    # eight between calls.
    var c: Int
    var lc: Int

    def __init__(out self, var out: List[UInt8]):
        """Write after the bytes `out` holds."""
        self.out = out^
        self.c = 0
        self.lc = 0

    def put(mut self, count: Int, bits: Int):
        """Write the low `count` bits of `bits`, sixteen at a time."""
        var left = count
        while left > 0:
            var k = min(left, 16)
            left -= k
            self.c = (self.c << k) | ((bits >> left) & ((1 << k) - 1))
            self.lc += k
            while self.lc >= 8:
                self.lc -= 8
                self.out.append(UInt8((self.c >> self.lc) & 0xFF))
            self.c &= (1 << self.lc) - 1

    def finish(deinit self) -> List[UInt8]:
        """Give up the bytes, with the bits of a last part byte at the top
        of one more byte.

        Returns:
            Everything written.
        """
        if self.lc > 0:
            self.out.append(UInt8((self.c << (8 - self.lc)) & 0xFF))
        return self.out^


def _before(frequency: List[Int], a: Int, b: Int) -> Bool:
    """Return True if symbol `a` leaves the heap before symbol `b`: the
    less frequent first, and of two as frequent, the lower. three.js's
    heap takes the same order, so the code lengths are its lengths.

    The two make one key, the frequency and then the symbol. A frequency
    is at most the count of a block's words, so the key fits."""
    return frequency[a] * HUF_ENCSIZE + a < frequency[b] * HUF_ENCSIZE + b


def _sift_down(
    mut heap: List[Int], frequency: List[Int], start: Int, size: Int
):
    """Move the symbol at `start` down to its place in the heap."""
    var at = start
    while 2 * at + 1 < size:
        var child = 2 * at + 1
        if child + 1 < size:
            if _before(frequency, heap[child + 1], heap[child]):
                child += 1
        if _before(frequency, heap[at], heap[child]):
            return
        heap.swap_elements(at, child)
        at = child


def _sift_up(mut heap: List[Int], frequency: List[Int], start: Int):
    """Move the symbol at `start` up to its place in the heap."""
    var at = start
    while at > 0:
        var parent = (at - 1) // 2
        if not _before(frequency, heap[at], heap[parent]):
            return
        heap.swap_elements(at, parent)
        at = parent


def _pop(mut heap: List[Int], frequency: List[Int]) -> Int:
    """Remove and return the first symbol of a heap that is not empty."""
    heap.swap_elements(0, len(heap) - 1)
    var first = heap.pop()
    _sift_down(heap, frequency, 0, len(heap))
    return first


def _code_lengths(var frequency: List[Int], first: Int, last: Int) -> List[Int]:
    """Return each symbol's Huffman code length: three.js's
    `hufBuildEncTable`, from OpenEXR.

    Symbol `last + 1` is added with a frequency of one. It marks a run of
    one symbol. Each step joins the two least frequent groups, and every
    symbol in the two groups gets one bit longer.

    Args:
        frequency: How often each symbol occurs.
        first: The smallest symbol that occurs.
        last: The largest symbol that occurs.

    Returns:
        The lengths, zero for a symbol that does not occur.
    """
    var rlc = last + 1
    frequency[rlc] = 1
    # Each symbol's next symbol in its group; the last links to itself.
    var link = List[Int](length=HUF_ENCSIZE, fill=0)
    var heap = List[Int]()
    # From the smallest symbol to the run marker. The loop always runs.
    for symbol in range(first, rlc + 1):  # pragma: no branch
        link[symbol] = symbol
        if frequency[symbol] != 0:
            heap.append(symbol)
    var start = len(heap) // 2 - 1
    while start >= 0:
        _sift_down(heap, frequency, start, len(heap))
        start -= 1
    var lengths = List[Int](length=HUF_ENCSIZE, fill=0)
    while len(heap) > 1:
        var mm = _pop(heap, frequency)
        var m = _pop(heap, frequency)
        frequency[m] += frequency[mm]
        heap.append(m)
        _sift_up(heap, frequency, len(heap) - 1)
        # Lengthen group `m` and append group `mm` to it.
        var j = m
        while True:
            lengths[j] += 1
            if link[j] == j:
                link[j] = mm
                break
            j = link[j]
        j = mm
        while True:
            lengths[j] += 1
            if link[j] == j:
                break
            j = link[j]
    return lengths^


def _canonical_codes(lengths: List[Int], first: Int, last: Int) -> List[Int]:
    """Return each symbol's canonical code: three.js's
    `hufCanonicalCodeTable`, the table `render.exr` builds when it reads.

    Longer codes take the smaller numbers. A block holds far fewer than
    the Fibonacci number of values that a code longer than
    `MAX_CODE_LENGTH` needs, so every length has a count.
    """
    var count = List[Int](length=MAX_CODE_LENGTH + 1, fill=0)
    # From the smallest symbol to the run marker. The loop always runs.
    for symbol in range(first, last + 1):  # pragma: no branch
        count[lengths[symbol]] += 1
    var code = 0
    # Fifty-eight lengths. The loop always runs.
    for length in range(MAX_CODE_LENGTH, 0, -1):  # pragma: no branch
        var next = (code + count[length]) >> 1
        count[length] = code
        code = next
    var codes = List[Int](length=HUF_ENCSIZE, fill=0)
    # From the smallest symbol to the run marker. The loop always runs.
    for symbol in range(first, last + 1):  # pragma: no branch
        var length = lengths[symbol]
        if length > 0:
            codes[symbol] = count[length]
            count[length] += 1
    return codes^


def _pack_lengths(
    lengths: List[Int], first: Int, last: Int, mut writer: _BitWriter
):
    """Write the code lengths of symbols `first` to `last`: three.js's
    `hufPackEncTable`.

    Six bits a length. A run of two to five zero lengths is one code from
    59 to 62. A longer run is 63 and eight more bits. Symbol `last` is
    the run marker, which always has a length, so no run of zeros reaches
    it. `render.exr` reads the table back.
    """
    var symbol = first
    while symbol <= last:
        var length = lengths[symbol]
        if length == 0:
            var run = 1
            while run < LONGEST_LONG_RUN:
                if lengths[symbol + 1] != 0:
                    break
                symbol += 1
                run += 1
            if run >= SHORTEST_LONG_RUN:
                writer.put(6, LONG_ZEROCODE_RUN)
                writer.put(8, run - SHORTEST_LONG_RUN)
                symbol += 1
                continue
            if run >= 2:
                writer.put(6, SHORT_ZEROCODE_RUN + run - 2)
                symbol += 1
                continue
        writer.put(6, length)
        symbol += 1
    if writer.lc > 0:
        writer.put(8 - writer.lc, 0)


def _send(
    mut writer: _BitWriter,
    codes: List[Int],
    lengths: List[Int],
    rlc: Int,
    symbol: Int,
    repeats: Int,
):
    """Write a symbol and how many more times it repeats: three.js's
    `sendCode`. A run code is written where it is shorter."""
    if lengths[symbol] + lengths[rlc] + 8 < lengths[symbol] * repeats:
        writer.put(lengths[symbol], codes[symbol])
        writer.put(lengths[rlc], codes[rlc])
        writer.put(8, repeats)
        return
    # A symbol is written once or more. The loop always runs.
    for _ in range(repeats + 1):  # pragma: no branch
        writer.put(lengths[symbol], codes[symbol])


def _huffman(values: List[Int]) -> List[UInt8]:
    """Return values Huffman coded, with the header and the code table
    that `render.exr.huffman_decode` reads: three.js's `hufCompress`.

    three.js gives up when the coded values would not fit in the raw
    block. The caller writes the raw block then, because a PIZ block is
    longer than its Huffman data, so this does not stop early.
    """
    var frequency = List[Int](length=HUF_ENCSIZE, fill=0)
    var first = USHORT_RANGE
    var last = 0
    # A block holds one value or more. The loop always runs.
    for value in values:  # pragma: no branch
        frequency[value] += 1
        first = min(first, value)
        last = max(last, value)
    var lengths = _code_lengths(frequency^, first, last)
    var rlc = last + 1
    var codes = _canonical_codes(lengths, first, rlc)
    var writer = _BitWriter(List[UInt8](length=20, fill=0))
    _pack_lengths(lengths, first, rlc, writer)
    var table_length = len(writer.out) - 20
    var data_start = len(writer.out)
    var symbol = values[0]
    var repeats = 0
    # A block holds four words or more. The loop always runs.
    for i in range(1, len(values)):  # pragma: no branch
        var next = values[i]
        if next == symbol:
            if repeats < MAX_HUFFMAN_RUN:
                repeats += 1
                continue
        _send(writer, codes, lengths, rlc, symbol, repeats)
        repeats = 0
        symbol = next
    _send(writer, codes, lengths, rlc, symbol, repeats)
    var bits = (len(writer.out) - data_start) * 8 + writer.lc
    var out = writer^.finish()
    store_little_endian(out, 0, first, 4)
    store_little_endian(out, 4, rlc, 4)
    store_little_endian(out, 8, table_length, 4)
    store_little_endian(out, 12, bits, 4)
    return out^


def _piz(
    raw: List[UInt8], start: Int, end: Int, width: Int, size: Int
) -> List[UInt8]:
    """Return a block PIZ compressed: three.js's `compressPIZ`, from
    OpenEXR's `PizCompressor`.

    The block's sixteen-bit words are laid out a channel at a time. A
    bitmap marks the words that occur, and a table maps each to its rank
    among them, zero first. Each channel goes through the wavelet, a
    float channel as two interleaved halves, and then all of them through
    one Huffman code. `render.exr.piz_decode` reads it.

    Args:
        raw: The lines, each with its A, B, G and R runs.
        start: The block's first byte.
        end: The byte after the block.
        width: The texels a line.
        size: The bytes a sample: two for a half, four for a float.

    Returns:
        The two bounds of the bitmap, its bytes, the length of the
        Huffman data and that data.
    """
    var per = size // 2
    var line = width * size
    var lines = (end - start) // (line * 4)
    var count = (end - start) // 2
    var buffer = List[Int](length=count, fill=0)
    # A block has one line or more. The loop always runs.
    for y in range(lines):  # pragma: no branch
        # Four channels. The loop always runs.
        for c in range(4):  # pragma: no branch
            var src = start + (y * 4 + c) * line
            var dst = (c * lines + y) * line // 2
            # A channel's run has one word or more. The loop always runs.
            for i in range(line // 2):  # pragma: no branch
                buffer[dst + i] = Int(raw[src + 2 * i]) | (
                    Int(raw[src + 2 * i + 1]) << 8
                )
    var bitmap = List[UInt8](length=BITMAP_SIZE, fill=0)
    # A block holds one word or more. The loop always runs.
    for value in buffer:  # pragma: no branch
        bitmap[value >> 3] |= UInt8(1 << (value & 7))
    # Zero is always in the table, so its bit is not stored.
    bitmap[0] &= 0xFE
    # three.js's bounds when no byte is set: the last byte and the first.
    var smallest = BITMAP_SIZE - 1
    var largest = 0
    # Every byte of the bitmap. The loop always runs.
    for i in range(BITMAP_SIZE):  # pragma: no branch
        if bitmap[i] != 0:
            smallest = min(smallest, i)
            largest = i
    var lut = List[Int](length=USHORT_RANGE, fill=0)
    var top = 0
    # The words the set bytes cover. With no byte set there are none.
    for value in range(smallest * 8, (largest + 1) * 8):
        if (Int(bitmap[value >> 3]) >> (value & 7)) & 1 == 1:
            top += 1
            lut[value] = top
    # A block holds one word or more. The loop always runs.
    for i in range(count):  # pragma: no branch
        buffer[i] = lut[buffer[i]]
    # Four channels. The loop always runs.
    for c in range(4):  # pragma: no branch
        # One or two halves a sample. The loop always runs.
        for j in range(per):  # pragma: no branch
            _wavelet_encode(
                buffer,
                c * width * lines * per + j,
                width,
                per,
                lines,
                per * width,
                top,
            )
    var coded = _huffman(buffer)
    var bitmap_length = max(largest - smallest + 1, 0)
    var out = List[UInt8](capacity=8 + bitmap_length + len(coded))
    append_little_endian_u16(out, smallest)
    append_little_endian_u16(out, largest)
    out.extend(Span(bitmap)[smallest : smallest + bitmap_length])
    append_little_endian_u32(out, len(coded))
    out.extend(Span(coded))
    return out^


def _write(
    width: Int,
    height: Int,
    values: List[Float64],
    compression: ExrCompression,
    type: ExrPixelType,
) raises -> List[UInt8]:
    """Write the file from the values, four a texel from the bottom row
    up: three.js's `reorganizeDataBuffer`, `compressData` and
    `fillData`."""
    var size = 2 * type.value
    var lines = lines_per_block(compression)
    var blocks = (height + lines - 1) // lines
    # The lines from the top down, each with its A, B, G and R runs.
    var raw = List[UInt8](length=width * height * 4 * size, fill=0)
    # The height is one or more. The loop always runs.
    for y in range(height):  # pragma: no branch
        var line = (height - y - 1) * width * 4 * size
        # The width is one or more. The loop always runs.
        for x in range(width):  # pragma: no branch
            var i = (y * width + x) * 4
            # A, B, G and R, as three.js writes them.
            # Four channels. The loop always runs.
            for c in range(4):  # pragma: no branch
                var at = line + c * width * size + x * size
                var value = values[i + 3 - c]
                var bits: Int
                if type == HALF_SAMPLES:
                    # three.js's clamp gives the processor's NaN, whose
                    # sign is set on x86-64.
                    bits = 0xFE00 if isnan(value) else Int(to_half_float(value))
                elif isnan(value):
                    # JavaScript holds one NaN, with no payload.
                    bits = 0x7FC00000
                else:
                    bits = Int(bitcast[DType.uint32](Float32(value)))
                store_little_endian(raw, at, bits, size)
    var chunks = List[List[UInt8]]()
    var block_size = width * 4 * lines * size
    # There is one block or more. The loop always runs.
    for b in range(blocks):  # pragma: no branch
        var start = block_size * b
        var end = min(start + block_size, len(raw))
        if compression == NO_COMPRESSION:
            chunks.append(copy_byte_range(raw, start, end))
            continue
        var packed: List[UInt8]
        if compression == PIZ_COMPRESSION:
            packed = _piz(raw, start, end, width, size)
        elif compression == RLE_COMPRESSION:
            packed = _run_length(_predicted(raw, start, end))
        else:
            packed = zlib_deflate(_predicted(raw, start, end))
        # A block that is not made smaller is read as raw lines.
        if len(packed) >= end - start:
            chunks.append(copy_byte_range(raw, start, end))
        else:
            chunks.append(packed^)
    var out = List[UInt8]()
    append_little_endian_u32(out, 20000630)
    append_little_endian_u32(out, 2)
    _attribute(out, "compression", "compression", 1)
    out.append(UInt8(compression.value))
    _attribute(out, "screenWindowCenter", "v2f", 8)
    append_little_endian_u32(out, 0)
    append_little_endian_u32(out, 0)
    _attribute(out, "screenWindowWidth", "float", 4)
    append_little_endian_u32(out, Int(bitcast[DType.uint32](Float32(1))))
    _attribute(out, "pixelAspectRatio", "float", 4)
    append_little_endian_u32(out, Int(bitcast[DType.uint32](Float32(1))))
    _attribute(out, "lineOrder", "lineOrder", 1)
    out.append(0)
    # Two windows. The loop always runs.
    for name in ["dataWindow", "displayWindow"]:  # pragma: no branch
        _attribute(out, name, "box2i", 16)
        append_little_endian_u32(out, 0)
        append_little_endian_u32(out, 0)
        append_little_endian_u32(out, width - 1)
        append_little_endian_u32(out, height - 1)
    _attribute(out, "channels", "chlist", 4 * 18 + 1)
    # Four channels. The loop always runs.
    for name in ["A", "B", "G", "R"]:  # pragma: no branch
        _push_string(out, name)
        append_little_endian_u32(out, type.value)
        append_little_endian_u32(out, 0)
        append_little_endian_u32(out, 1)
        append_little_endian_u32(out, 1)
    out.append(0)
    out.append(0)
    var offset = len(out) + blocks * 8
    # There is one block or more. The loop always runs.
    for chunk in chunks:  # pragma: no branch
        append_little_endian(out, offset, 8)
        offset += len(chunk) + 8
    # There is one block or more. The loop always runs.
    for b in range(blocks):  # pragma: no branch
        append_little_endian_u32(out, b * lines)
        append_little_endian_u32(out, len(chunks[b]))
        out.extend(Span(chunks[b]))
    return out^


def export_exr(
    width: Int,
    height: Int,
    data: List[Float32],
    compression: ExrCompression = ZIP_COMPRESSION,
    type: ExrPixelType = HALF_SAMPLES,
) raises -> List[UInt8]:
    """Return an EXR file of RGBA floats, as three.js's `EXRExporter`
    writes a `FloatType` `DataTexture`.

    Args:
        width: The width in texels.
        height: The height in texels.
        data: Four values a texel, from the bottom row up.
        compression: `NO_COMPRESSION`, `RLE_COMPRESSION`,
            `ZIPS_COMPRESSION`, `ZIP_COMPRESSION`, three.js's default,
            or `PIZ_COMPRESSION`.
        type: `HALF_SAMPLES`, three.js's default, or `FLOAT_SAMPLES`.

    Returns:
        The file.

    Raises:
        Error: If the image has no texels, its byte buffer does not fit,
            the data is not four values a texel, or the compression or
            the type is not one of these.
    """
    _check(width, height, len(data), compression, type)
    var values = List[Float64](capacity=len(data))
    # The data holds four values or more. The loop always runs.
    for v in data:  # pragma: no branch
        values.append(Float64(v))
    return _write(width, height, values, compression, type)


def export_exr_half(
    width: Int,
    height: Int,
    data: List[UInt16],
    compression: ExrCompression = ZIP_COMPRESSION,
    type: ExrPixelType = HALF_SAMPLES,
) raises -> List[UInt8]:
    """Return an EXR file of RGBA halves, as three.js's `EXRExporter`
    writes a `HalfFloatType` `DataTexture`.

    Each half is read as a number and written again, so a NaN loses
    its payload, as in three.js.

    Args:
        width: The width in texels.
        height: The height in texels.
        data: The bits of four halves a texel, from the bottom row up.
        compression: `NO_COMPRESSION`, `RLE_COMPRESSION`,
            `ZIPS_COMPRESSION`, `ZIP_COMPRESSION`, three.js's default,
            or `PIZ_COMPRESSION`.
        type: `HALF_SAMPLES`, three.js's default, or `FLOAT_SAMPLES`.

    Returns:
        The file.

    Raises:
        Error: If the image has no texels, its byte buffer does not fit,
            the data is not four values a texel, or the compression or
            the type is not one of these.
    """
    _check(width, height, len(data), compression, type)
    var values = List[Float64](capacity=len(data))
    # The data holds four values or more. The loop always runs.
    for v in data:  # pragma: no branch
        values.append(Float64(half_to_float(v)))
    return _write(width, height, values, compression, type)


def export_exr_image(
    image: FloatImage,
    compression: ExrCompression = ZIP_COMPRESSION,
    type: ExrPixelType = HALF_SAMPLES,
) raises -> List[UInt8]:
    """Return an EXR file of an image, which `render.exr.decode` reads
    back with its top row at the top.

    Args:
        image: The image, from the top row down.
        compression: `NO_COMPRESSION`, `RLE_COMPRESSION`,
            `ZIPS_COMPRESSION`, `ZIP_COMPRESSION`, three.js's default,
            or `PIZ_COMPRESSION`.
        type: `HALF_SAMPLES`, three.js's default, or `FLOAT_SAMPLES`.

    Returns:
        The file.

    Raises:
        Error: If the image has no texels, its byte buffer does not fit,
            its pixels are not four values a texel, or the compression
            or the type is not one of these.
    """
    _check(
        image.width,
        image.height,
        len(image.pixels),
        compression,
        type,
    )
    var row = image.width * 4
    var data = List[Float32](capacity=len(image.pixels))
    var y = image.height - 1
    while y >= 0:
        # A row has four values or more. The loop always runs.
        for i in range(row):  # pragma: no branch
            data.append(image.pixels[y * row + i])
        y -= 1
    return export_exr(image.width, image.height, data, compression, type)
