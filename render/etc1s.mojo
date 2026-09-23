# Copyright (c) 2026 Seth Kitchen, PE
# SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
# Noncommercial use is free; commercial use requires a paid license.
# See LICENSE, LICENSE-COMMERCIAL.md and THIRD-PARTY-NOTICES.md.

"""Basis Universal ETC1S images, stored with BasisLZ supercompression,
decoded to RGBA bytes. Ported from `basisu_lowlevel_etc1s_transcoder` and
`bitwise_decoder` in Binomial's `basisu_transcoder.cpp` (Apache-2.0).

A KTX 2.0 file with the ETC1S color model keeps two codebooks and four
Huffman tables in its supercompression global data, and each image as a
slice of Huffman-coded indices into the codebooks. three.js transcodes
the slices with the Basis Universal WebAssembly transcoder. Here they
decode on the host to the same RGBA bytes that transcoder gives for its
`RGBA32` target.

**An ETC1S block is an ETC1 block with one color.** Both halves share a
5-bit base color and an intensity table, and each texel has a two-bit
selector. The endpoint codebook holds the colors and tables, and the
selector codebook holds the sixteen selectors of a block.

**The global data.** A header gives the codebook sizes and the byte
lengths of the endpoints, the selectors and the tables. An image
descriptor per image gives where its color slice, and its alpha slice,
lie in its level. The codebooks are delta coded with Huffman codes, and
the tables are the four Huffman codes a slice reads.

**A slice.** For each 2x2 group of blocks, a symbol says where each
block's endpoint comes from: the block to the left, above, above left,
or a Huffman-coded delta from the previous endpoint. A run of groups can
repeat the last symbol. Each block's selector is a codebook index, an
index into a short history of recent selectors, or part of a run of the
most recent one.

**Alpha is a second slice.** A file with alpha stores it as a second
ETC1S image whose green channel is the alpha.

**Bits run low to high.** Huffman codes are canonical and read one bit at
a time with the first bit the code's highest, as DEFLATE reads them. A
reader past the end of its bytes reads zeros, as Binomial's does.
"""

# The largest Huffman code and the size of the code-length alphabet.
comptime MAX_CODE_BITS = 16
comptime CODE_LENGTH_CODES = 21
# The endpoint prediction symbol that repeats the last one.
comptime REPEAT_LAST_PREDICTION = 256
# The selector history run code that reads a longer count.
comptime LONG_SELECTOR_RUN = 63
# The size of the global data header and of one image descriptor.
comptime GLOBAL_HEADER_BYTES = 20
comptime IMAGE_DESC_BYTES = 20
# The image flag of a P-frame of a video.
comptime P_FRAME_FLAG = 2


def _code_length_order() -> List[Int]:
    """Return which code length each stored code-length code size is for."""
    return [
        17, 18, 19, 20, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1,
        15, 16,
    ]  # fmt: skip


def etc1s_intensities() -> List[Int]:
    """Return the eight ETC1 intensity tables in selector order.

    Returns:
        Thirty-two offsets: table `t` is `[4t]` to `[4t + 3]`, from the
        largest negative offset to the largest positive one.
    """
    return [
        -8, -2, 2, 8, -17, -5, 5, 17, -29, -9, 9, 29, -42, -13, 13, 42,
        -60, -18, 18, 60, -80, -24, 24, 80, -106, -33, 33, 106,
        -183, -47, 47, 183,
    ]  # fmt: skip


struct _Bits(Movable):
    """A bit reader, low bit first, that gives zeros past its end."""

    var data: List[UInt8]
    var position: Int

    def __init__(out self, bytes: List[UInt8], start: Int, length: Int):
        self.data = List[UInt8](bytes[start : start + length])
        self.position = 0

    def read(mut self, count: Int) -> Int:
        """Return the next `count` bits as a number, low bit first."""
        var value = 0
        # Every field the format stores is at least one bit wide.
        for bit in range(count):  # pragma: no branch
            value |= self.bit() << bit
        return value

    def bit(mut self) -> Int:
        """Return the next bit, zero past the end."""
        var at = self.position >> 3
        var shift = self.position & 7
        self.position += 1
        return (Int(self.data[at]) >> shift) & 1 if at < len(self.data) else 0

    def vlc(mut self, chunk: Int) -> Int:
        """Return a number stored in chunks of `chunk` bits, each followed
        by a bit that says whether another chunk follows."""
        var value = 0
        var shift = 0
        var more = 1
        while more == 1:
            value |= self.read(chunk) << shift
            shift += chunk
            more = self.bit() * Int(shift < 32)
        return value


struct _Huffman(Copyable, Movable):
    """A canonical Huffman code: how many codes of each length, and the
    symbols in code order."""

    var counts: List[Int]
    var symbols: List[Int]

    def __init__(out self):
        """Make an empty code, which decodes nothing."""
        self.counts = List[Int](length=MAX_CODE_BITS + 1, fill=0)
        self.symbols = List[Int]()

    def __init__(out self, sizes: List[Int]) raises:
        """Build the code from each symbol's code length, zero for a symbol
        that has no code.

        Raises:
            Error: If the lengths neither form a complete code nor give one
                symbol a code.
        """
        self.counts = List[Int](length=MAX_CODE_BITS + 1, fill=0)
        self.symbols = List[Int]()
        for length in range(1, MAX_CODE_BITS + 1):  # pragma: no branch
            for symbol in range(len(sizes)):  # pragma: no branch
                if sizes[symbol] == length:
                    self.counts[length] += 1
                    self.symbols.append(symbol)
        var space = 0
        for length in range(1, MAX_CODE_BITS + 1):  # pragma: no branch
            space += self.counts[length] << (MAX_CODE_BITS - length)
        if not _complete(space, len(self.symbols)):
            raise Error("ETC1S: a Huffman table is not a complete code")

    def empty(self) -> Bool:
        """Return True if no symbol has a code."""
        return len(self.symbols) == 0

    def decode(self, mut bits: _Bits) raises -> Int:
        """Return the next symbol.

        Raises:
            Error: If no code matches the bits; only a code of one symbol
                leaves bits unmatched.
        """
        var code = 0
        var first = 0
        var index = 0
        for length in range(1, MAX_CODE_BITS + 1):  # pragma: no branch
            code |= bits.bit()
            var count = self.counts[length]
            if code - first < count:
                return self.symbols[index + code - first]
            index += count
            first = (first + count) << 1
            code <<= 1
        raise Error("ETC1S: no Huffman code matches the bits read")


def _complete(space: Int, used: Int) -> Bool:
    """Return True if codes filling `space` of 65536 make a usable code:
    the whole of it, or one symbol."""
    return space == 1 << MAX_CODE_BITS or used == 1


def _outside_count(count: Int) -> Bool:
    """Return True if a code-length code count is not 1 to 21."""
    return count < 1 or count > CODE_LENGTH_CODES


def _read_table(mut bits: _Bits) raises -> _Huffman:
    """Read a Huffman table: code lengths coded with a code of their own.

    Args:
        bits: The reader, at the table.

    Returns:
        The table, empty if it names no symbols.

    Raises:
        Error: If the table is malformed.
    """
    var total = bits.read(14)
    if total == 0:
        return _Huffman()
    var count = bits.read(5)
    if _outside_count(count):
        raise Error("ETC1S: a Huffman table has a bad code-length count")
    var order = _code_length_order()
    var length_sizes = List[Int](length=CODE_LENGTH_CODES, fill=0)
    for index in range(count):  # pragma: no branch
        length_sizes[order[index]] = bits.read(3)
    var lengths = _Huffman(length_sizes)
    var sizes = List[Int](length=total, fill=0)
    var at = 0
    while at < total:
        var code = lengths.decode(bits)
        if code <= 16:
            sizes[at] = code
            at += 1
        elif code == 17:
            at += bits.read(3) + 3
        elif code == 18:
            at += bits.read(7) + 11
        else:
            if at == 0:
                raise Error("ETC1S: a Huffman table repeats before a length")
            var repeat: Int
            if code == 19:
                repeat = bits.read(2) + 3
            else:
                repeat = bits.read(7) + 7
            var previous = sizes[at - 1]
            if previous == 0:
                raise Error("ETC1S: a Huffman table repeats a zero length")
            for _ in range(repeat):  # pragma: no branch
                if at >= total:
                    raise Error("ETC1S: a Huffman table runs past its symbols")
                sizes[at] = previous
                at += 1
    if at != total:
        raise Error("ETC1S: a Huffman table runs past its symbols")
    return _Huffman(sizes)


def _u32(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian word at `at`."""
    return (
        Int(bytes[at])
        | (Int(bytes[at + 1]) << 8)
        | (Int(bytes[at + 2]) << 16)
        | (Int(bytes[at + 3]) << 24)
    )


def _u16(bytes: List[UInt8], at: Int) -> Int:
    """Return the little-endian half word at `at`."""
    return Int(bytes[at]) | (Int(bytes[at + 1]) << 8)


struct Etc1sGlobal(Movable):
    """A KTX 2.0 file's BasisLZ global data, decoded: the endpoint and
    selector codebooks, the slice tables and the image descriptors."""

    var endpoints: List[Int]
    """Four numbers per endpoint: the 5-bit red, green and blue, and the
    intensity table."""
    var selectors: List[Int]
    """Four bytes per selector: one per row, two bits per texel."""
    var prediction: _Huffman
    """The code of the endpoint prediction symbols."""
    var delta: _Huffman
    """The code of the endpoint index deltas."""
    var selector: _Huffman
    """The code of the selector symbols."""
    var run: _Huffman
    """The code of the selector run lengths."""
    var history: Int
    """How many recent selectors a slice keeps."""
    var images: List[Int]
    """Five numbers per image: its flags, and the offset and length of its
    color slice and of its alpha slice."""

    def __init__(out self):
        """Make empty global data, for a file that is not ETC1S."""
        self.endpoints = List[Int]()
        self.selectors = List[Int]()
        self.prediction = _Huffman()
        self.delta = _Huffman()
        self.selector = _Huffman()
        self.run = _Huffman()
        self.history = 0
        self.images = List[Int]()

    def __init__(
        out self, bytes: List[UInt8], images: Int, has_alpha: Bool
    ) raises:
        """Decode the global data.

        Args:
            bytes: The supercompression global data.
            images: How many images the file holds: levels times layers
                times faces.
            has_alpha: Whether each image has an alpha slice.

        Raises:
            Error: If the data is shorter than its header says, a count or
                a length is zero, an image is a P-frame of a video or lacks
                a slice, or a codebook or table is malformed.
        """
        self.endpoints = List[Int]()
        self.selectors = List[Int]()
        self.prediction = _Huffman()
        self.delta = _Huffman()
        self.selector = _Huffman()
        self.run = _Huffman()
        self.history = 0
        self.images = List[Int]()
        if len(bytes) < GLOBAL_HEADER_BYTES:
            raise Error("ETC1S: the global data is shorter than its header")
        var endpoint_count = _u16(bytes, 0)
        var selector_count = _u16(bytes, 2)
        var endpoint_bytes = _u32(bytes, 4)
        var selector_bytes = _u32(bytes, 8)
        var table_bytes = _u32(bytes, 12)
        var extended_bytes = _u32(bytes, 16)
        if _any_zero(
            endpoint_count,
            selector_count,
            endpoint_bytes,
            selector_bytes,
            table_bytes,
        ):
            raise Error("ETC1S: the global data names an empty codebook")
        var start = GLOBAL_HEADER_BYTES + images * IMAGE_DESC_BYTES
        var end = (
            start
            + endpoint_bytes
            + selector_bytes
            + table_bytes
            + extended_bytes
        )
        if end > len(bytes):
            raise Error("ETC1S: the global data is shorter than it says")
        for image in range(images):  # pragma: no branch
            var at = GLOBAL_HEADER_BYTES + image * IMAGE_DESC_BYTES
            for field in range(5):  # pragma: no branch
                self.images.append(_u32(bytes, at + field * 4))
            if self.images[image * 5] & P_FRAME_FLAG != 0:
                raise Error("ETC1S: video P-frames are not ported")
            if self.images[image * 5 + 2] == 0:
                raise Error("ETC1S: an image has no color slice")
            if has_alpha:
                if self.images[image * 5 + 4] == 0:
                    raise Error("ETC1S: an image has no alpha slice")
        var tables = _Bits(
            bytes, start + endpoint_bytes + selector_bytes, table_bytes
        )
        self.prediction = _read_table(tables)
        self.delta = _read_table(tables)
        self.selector = _read_table(tables)
        self.run = _read_table(tables)
        self.history = tables.read(13)
        if _any_empty(self.prediction, self.delta, self.selector, self.run):
            raise Error("ETC1S: a slice table is empty")
        if self.history == 0:
            raise Error("ETC1S: the selector history is empty")
        self.endpoints = _read_endpoints(
            _Bits(bytes, start, endpoint_bytes), endpoint_count
        )
        self.selectors = _read_selectors(
            _Bits(bytes, start + endpoint_bytes, selector_bytes),
            selector_count,
        )


def _any_zero(a: Int, b: Int, c: Int, d: Int, e: Int) -> Bool:
    """Return True if any of five numbers is zero."""
    return a == 0 or b == 0 or c == 0 or d == 0 or e == 0


def _any_empty(a: _Huffman, b: _Huffman, c: _Huffman, d: _Huffman) -> Bool:
    """Return True if any of four tables is empty."""
    return a.empty() or b.empty() or c.empty() or d.empty()


def _read_endpoints(var bits: _Bits, count: Int) raises -> List[Int]:
    """Read the endpoint codebook.

    Each endpoint's intensity table and 5-bit color are deltas from the
    previous one's. The code of a channel's delta depends on how large the
    previous value of that channel is.

    Args:
        bits: The endpoint data.
        count: How many endpoints there are.

    Returns:
        Four numbers per endpoint; see `Etc1sGlobal.endpoints`.

    Raises:
        Error: If a table is empty or malformed.
    """
    var color_codes = List[_Huffman]()
    for _ in range(3):  # pragma: no branch
        color_codes.append(_read_table(bits))
    var intensity_code = _read_table(bits)
    if _any_empty(
        color_codes[0], color_codes[1], color_codes[2], intensity_code
    ):
        raise Error("ETC1S: an endpoint codebook table is empty")
    var gray = bits.read(1) == 1
    var channels = 1 if gray else 3
    var previous: List[Int] = [16, 16, 16]
    var intensity = 0
    var out = List[Int]()
    for _ in range(count):  # pragma: no branch
        intensity = (intensity + intensity_code.decode(bits)) & 7
        for channel in range(channels):  # pragma: no branch
            var model = 2
            if previous[channel] <= 9:
                model = 0
            elif previous[channel] <= 21:
                model = 1
            previous[channel] = (
                previous[channel] + color_codes[model].decode(bits)
            ) & 31
        if gray:
            previous[1] = previous[0]
            previous[2] = previous[0]
        out.extend([previous[0], previous[1], previous[2], intensity])
    return out^


def _lacks_table(count: Int, code: _Huffman) -> Bool:
    """Return True if more than one selector has no table to decode by."""
    return count > 1 and code.empty()


def _read_selectors(var bits: _Bits, count: Int) raises -> List[Int]:
    """Read the selector codebook: raw bytes, or each selector's bytes
    exclusive-or'd with the previous selector's through a Huffman code.

    Args:
        bits: The selector data.
        count: How many selectors there are.

    Returns:
        Four bytes per selector.

    Raises:
        Error: If the codebook is a global or hybrid one, which the
            transcoder does not read either, or its table is malformed.
    """
    if bits.read(1) == 1:
        raise Error("ETC1S: global selector codebooks are not supported")
    if bits.read(1) == 1:
        raise Error("ETC1S: hybrid selector codebooks are not supported")
    var out = List[Int]()
    if bits.read(1) == 1:
        for _ in range(count * 4):  # pragma: no branch
            out.append(bits.read(8))
        return out^
    var code = _read_table(bits)
    if _lacks_table(count, code):
        raise Error("ETC1S: the selector codebook table is empty")
    for _ in range(4):  # pragma: no branch
        out.append(bits.read(8))
    for index in range(4, count * 4):
        out.append(code.decode(bits) ^ out[index - 4])
    return out^


def etc1s_image(
    global_data: Etc1sGlobal,
    image: Int,
    level: List[UInt8],
    width: Int,
    height: Int,
    has_alpha: Bool,
) raises -> List[UInt8]:
    """Return one image of an ETC1S file as RGBA bytes, row-major.

    Args:
        global_data: The file's decoded global data.
        image: Which image: `(level * layers + layer) * faces + face`.
        level: The bytes of the image's level.
        width: The level's width in texels.
        height: Its height.
        has_alpha: Whether the image has an alpha slice.

    Returns:
        `width * height * 4` bytes. Alpha is 255 when there is no alpha
        slice.

    Raises:
        Error: If a slice lies outside the level, or is malformed.
    """
    var desc = List[Int](global_data.images[image * 5 : image * 5 + 5])
    var out = List[UInt8](length=width * height * 4, fill=255)
    if has_alpha:
        _slice(global_data, level, desc[3], desc[4], width, height, out, True)
    _slice(global_data, level, desc[1], desc[2], width, height, out, False)
    return out^


def _slice(
    global_data: Etc1sGlobal,
    level: List[UInt8],
    offset: Int,
    length: Int,
    width: Int,
    height: Int,
    mut out: List[UInt8],
    alpha: Bool,
) raises:
    """Decode one slice into `out`: its colors, or its green as alpha.

    Args:
        global_data: The codebooks and tables.
        level: The level's bytes.
        offset: Where the slice starts in them.
        length: How many bytes it takes.
        width: The image's width in texels.
        height: Its height.
        out: The RGBA image; written.
        alpha: Write the green of each texel to alpha, not the colors.

    Raises:
        Error: If the slice lies outside the level, or a prediction, a
            delta, a selector or a run is out of range.
    """
    if offset + length > len(level):
        raise Error("ETC1S: a slice lies outside its level")
    var bits = _Bits(level, offset, length)
    var across = (width + 3) // 4
    var down = (height + 3) // 4
    var intensities = etc1s_intensities()
    var endpoint_count = len(global_data.endpoints) // 4
    var selector_count = len(global_data.selectors) // 4
    var history = List[Int](length=global_data.history, fill=0)
    var rover = global_data.history // 2
    var history_run = selector_count + global_data.history
    var run = 0
    # Per column: each row's endpoint index, and the prediction bits the
    # next row of a 2x2 group reads.
    var rows = [
        List[Int](length=across, fill=0),
        List[Int](length=across, fill=0),
    ]
    var pending = List[Int](length=across, fill=0)
    var prediction = 0
    var last_symbol = 0
    var repeats = 0
    var endpoint = 0
    for by in range(down):  # pragma: no branch
        var here = by & 1
        for bx in range(across):  # pragma: no branch
            if bx & 1 == 0:
                if here == 0:
                    if repeats > 0:
                        repeats -= 1
                        prediction = last_symbol
                    else:
                        prediction = global_data.prediction.decode(bits)
                        if prediction == REPEAT_LAST_PREDICTION:
                            repeats = bits.vlc(4) + 2
                            prediction = last_symbol
                        else:
                            last_symbol = prediction
                    pending[bx] = prediction >> 4
                else:
                    prediction = pending[bx]
            var predict = prediction & 3
            prediction >>= 2
            if predict == 0:
                if bx == 0:
                    raise Error(
                        "ETC1S: a block at the left edge copies its left"
                    )
            elif predict == 1:
                if by == 0:
                    raise Error("ETC1S: a block at the top edge copies above")
                endpoint = rows[here ^ 1][bx]
            elif predict == 2:
                if bx * by == 0:
                    raise Error("ETC1S: a block at an edge copies above left")
                endpoint = rows[here ^ 1][bx - 1]
            else:
                endpoint += global_data.delta.decode(bits)
                if endpoint >= endpoint_count:
                    endpoint -= endpoint_count
                if endpoint >= endpoint_count:
                    raise Error("ETC1S: an endpoint delta is out of range")
            rows[here][bx] = endpoint
            var selector: Int
            if run > 0:
                run -= 1
                selector = history[0]
            else:
                var symbol = global_data.selector.decode(bits)
                if symbol == history_run:
                    var length = global_data.run.decode(bits) + 3
                    if length == LONG_SELECTOR_RUN + 3:
                        length = bits.vlc(7) + 3
                    if length > across * down:
                        raise Error(
                            "ETC1S: a selector run is longer than the image"
                        )
                    run = length - 1
                    symbol = selector_count
                if symbol < selector_count:
                    selector = symbol
                    history[rover] = selector
                    rover += 1
                    if rover == len(history):
                        rover = len(history) // 2
                else:
                    var index = symbol - selector_count
                    if index >= len(history):
                        raise Error("ETC1S: a selector is not in the history")
                    selector = history[index]
                    history[index] = history[index // 2]
                    history[index // 2] = selector
            _write_block(
                global_data,
                endpoint,
                selector,
                intensities,
                bx,
                by,
                width,
                height,
                out,
                alpha,
            )


def _write_block(
    global_data: Etc1sGlobal,
    endpoint: Int,
    selector: Int,
    intensities: List[Int],
    bx: Int,
    by: Int,
    width: Int,
    height: Int,
    mut out: List[UInt8],
    alpha: Bool,
):
    """Write one block's texels that lie inside the image."""
    var colors = List[Int]()
    var table = global_data.endpoints[endpoint * 4 + 3]
    for step in range(4):  # pragma: no branch
        for channel in range(3):  # pragma: no branch
            var five = global_data.endpoints[endpoint * 4 + channel]
            var value = (five << 3) | (five >> 2)
            colors.append(
                max(0, min(255, value + intensities[table * 4 + step]))
            )
    for y in range(min(4, height - by * 4)):  # pragma: no branch
        var row = global_data.selectors[selector * 4 + y]
        for x in range(min(4, width - bx * 4)):  # pragma: no branch
            var step = (row >> (x * 2)) & 3
            var to = ((by * 4 + y) * width + bx * 4 + x) * 4
            if alpha:
                out[to + 3] = UInt8(colors[step * 3 + 1])
            else:
                for channel in range(3):  # pragma: no branch
                    out[to + channel] = UInt8(colors[step * 3 + channel])
